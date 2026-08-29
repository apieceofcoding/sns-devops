// sns-recommender: 타임라인 후보 게시글을 사용자 세그먼트에 맞춰 재정렬하는 추천 서비스.
//
// sns-app 이 타임라인을 조회할 때 Redis 에서 뽑은 후보 postId 목록을 이 서비스로 보내고,
// 재정렬된 순서를 돌려받는다. 상태를 갖지 않으므로 DB 도 캐시도 쓰지 않는다.
//
// 사용자는 릴리스 단계에 따라 두 세그먼트로 나뉜다.
//
//	ga    정식 출시된 안정 경로. 빠르다.
//	beta  새 추천 모델을 먼저 적용하는 실험 경로. 아직 최적화가 안 되어 느리다.
//
// beta 가 느린 것은 의도한 설정이다. 장애가 전체가 아니라 일부 사용자에게만
// 나타나야 메트릭, 트레이스, 로그를 이어야만 원인을 찾을 수 있기 때문이다.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	"log/slog"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"strconv"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.43.0"
	"go.opentelemetry.io/otel/trace"
)

const (
	serviceName = "sns-recommender"

	// 후보 목록 한 페이지치고는 넉넉한 상한이다.
	maxRequestBodyBytes = 1 << 20
)

type config struct {
	port     string
	fastMs   int
	slowMs   int
	jitterMs int
	otlpURL  string
}

type rankRequest struct {
	UserID  int64   `json:"userId"`
	PostIDs []int64 `json:"postIds"`
}

type rankResponse struct {
	UserID        int64   `json:"userId"`
	Segment       string  `json:"segment"`
	RankedPostIDs []int64 `json:"rankedPostIds"`
	TookMs        int64   `json:"tookMs"`
}

func main() {
	cfg := loadConfig()

	shutdown, err := initTracer(cfg.otlpURL)
	if err != nil {
		slog.Error("트레이서 초기화 실패", "error", err)
		os.Exit(1)
	}

	mux := http.NewServeMux()
	// 헬스체크는 otelhttp 바깥에 둔다. kubelet 이 주기적으로 부르므로 span 이 쌓이기만 한다.
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.Handle("POST /v1/rank", otelhttp.NewHandler(rankHandler(cfg), "POST /v1/rank"))

	srv := &http.Server{
		Addr:              ":" + cfg.port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		slog.Info("추천 서비스 시작",
			"port", cfg.port, "fastMs", cfg.fastMs, "slowMs", cfg.slowMs, "otlp", cfg.otlpURL)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("서버 종료", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
	shutdown(ctx)
	slog.Info("추천 서비스 정상 종료")
}

// rankHandler 는 후보 postId 목록을 받아 세그먼트별 지연을 흉내 낸 뒤 재정렬해 돌려준다.
func rankHandler(cfg config) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		span := trace.SpanFromContext(ctx)

		// 본문 크기를 제한한다. 한 페이지의 후보 목록이라 1MB 를 넘을 이유가 없고,
		// 제한이 없으면 큰 본문 하나로 메모리를 소진시킬 수 있다.
		r.Body = http.MaxBytesReader(w, r.Body, maxRequestBodyBytes)

		var req rankRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "본문을 읽을 수 없습니다")
			return
		}
		if req.UserID <= 0 {
			writeError(w, http.StatusBadRequest, "userId 가 필요합니다")
			return
		}

		segment := segmentOf(req.UserID)
		span.SetAttributes(
			attribute.Int64("user.id", req.UserID),
			attribute.String("user.segment", segment),
			attribute.Int("rank.candidates", len(req.PostIDs)),
		)

		start := time.Now()
		score(ctx, cfg, segment)
		ranked := rank(req.UserID, req.PostIDs)
		took := time.Since(start).Milliseconds()

		span.SetAttributes(attribute.Int64("rank.took_ms", took))

		logger(ctx).Info("랭킹 완료",
			"userId", req.UserID, "segment", segment,
			"candidates", len(req.PostIDs), "tookMs", took)

		writeJSON(w, http.StatusOK, rankResponse{
			UserID:        req.UserID,
			Segment:       segment,
			RankedPostIDs: ranked,
			TookMs:        took,
		})
	})
}

// score 는 추천 모델 추론을 흉내 낸다. beta 경로는 최적화가 안 되어 오래 걸린다.
func score(ctx context.Context, cfg config, segment string) {
	_, span := otel.Tracer(serviceName).Start(ctx, "model-inference")
	defer span.End()

	base := cfg.fastMs
	if segment == "beta" {
		base = cfg.slowMs
	}
	delay := base
	if cfg.jitterMs > 0 {
		delay += rand.Intn(cfg.jitterMs)
	}
	span.SetAttributes(
		attribute.String("model.variant", segment),
		attribute.Int("model.delay_ms", delay),
	)
	time.Sleep(time.Duration(delay) * time.Millisecond)
}

// rank 는 (userId, postId) 조합으로 결정되는 점수 내림차순으로 정렬한다.
// 같은 입력이면 항상 같은 순서가 나오므로 실습에서 재현할 수 있다.
func rank(userID int64, postIDs []int64) []int64 {
	ranked := make([]int64, len(postIDs))
	copy(ranked, postIDs)
	sort.SliceStable(ranked, func(i, j int) bool {
		return affinity(userID, ranked[i]) > affinity(userID, ranked[j])
	})
	return ranked
}

func affinity(userID, postID int64) uint32 {
	h := fnv.New32a()
	_, _ = fmt.Fprintf(h, "%d:%d", userID, postID)
	return h.Sum32()
}

// segmentOf 는 사용자를 릴리스 단계로 나눈다. 3의 배수가 beta 로, 약 33% 가 실험 경로를 탄다.
func segmentOf(userID int64) string {
	if userID%3 == 0 {
		return "beta"
	}
	return "ga"
}

// logger 는 현재 span 의 traceId 를 로그에 붙인다. Loki 에서 로그를 보다가
// 같은 traceId 의 트레이스로 이동할 수 있어야 하기 때문이다.
func logger(ctx context.Context) *slog.Logger {
	sc := trace.SpanContextFromContext(ctx)
	if !sc.IsValid() {
		return slog.Default()
	}
	return slog.With("trace_id", sc.TraceID().String(), "span_id", sc.SpanID().String())
}

func initTracer(otlpURL string) (func(context.Context), error) {
	ctx := context.Background()

	exporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpointURL(otlpURL+"/v1/traces"),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	res, err := resource.Merge(resource.Default(), resource.NewWithAttributes(
		semconv.SchemaURL,
		semconv.ServiceName(serviceName),
	))
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)
	otel.SetTracerProvider(tp)

	// sns-app 이 보낸 traceparent 헤더를 이어받으려면 W3C Trace Context 전파기가 필요하다.
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return func(ctx context.Context) { _ = tp.Shutdown(ctx) }, nil
}

func loadConfig() config {
	return config{
		port:     env("PORT", "8080"),
		fastMs:   envInt("FAST_MS", 40),
		slowMs:   envInt("SLOW_MS", 260),
		jitterMs: envInt("JITTER_MS", 60),
		otlpURL:  env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318"),
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
