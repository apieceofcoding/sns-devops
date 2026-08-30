package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sort"
	"strconv"
	"testing"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

var testConfig = config{fastMs: 0, slowMs: 0, jitterMs: 0}

func TestSegmentOf(t *testing.T) {
	cases := map[int64]string{1: "ga", 2: "ga", 3: "beta", 4: "ga", 6: "beta", 9: "beta"}
	for userID, want := range cases {
		if got := segmentOf(userID); got != want {
			t.Errorf("userId %d: %q 를 기대했지만 %q", userID, want, got)
		}
	}
}

func TestRankIsDeterministic(t *testing.T) {
	postIDs := []int64{101, 102, 103, 104, 105}

	first := rank(7, postIDs)
	second := rank(7, postIDs)

	if !equal(first, second) {
		t.Fatalf("같은 입력인데 순서가 다릅니다: %v vs %v", first, second)
	}
}

func TestRankPreservesCandidateSet(t *testing.T) {
	postIDs := []int64{101, 102, 103, 104, 105}

	ranked := rank(7, postIDs)

	if len(ranked) != len(postIDs) {
		t.Fatalf("후보 %d 개를 넣었는데 %d 개가 나왔습니다", len(postIDs), len(ranked))
	}
	got, want := append([]int64(nil), ranked...), append([]int64(nil), postIDs...)
	sort.Slice(got, func(i, j int) bool { return got[i] < got[j] })
	sort.Slice(want, func(i, j int) bool { return want[i] < want[j] })
	if !equal(got, want) {
		t.Errorf("후보 집합이 달라졌습니다: %v", ranked)
	}
}

func TestRankDoesNotMutateInput(t *testing.T) {
	postIDs := []int64{101, 102, 103, 104, 105}
	original := append([]int64(nil), postIDs...)

	rank(7, postIDs)

	if !equal(postIDs, original) {
		t.Errorf("입력 슬라이스가 변경되었습니다: %v", postIDs)
	}
}

func TestRankHandlerResponse(t *testing.T) {
	body, _ := json.Marshal(rankRequest{UserID: 3, PostIDs: []int64{101, 102, 103}})
	rec := httptest.NewRecorder()

	rankHandler(testConfig).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/rank", bytes.NewReader(body)))

	if rec.Code != http.StatusOK {
		t.Fatalf("200 을 기대했지만 %d", rec.Code)
	}
	var resp rankResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("응답을 읽을 수 없습니다: %v", err)
	}
	if resp.Segment != "beta" {
		t.Errorf("userId 3 은 beta 여야 하는데 %q", resp.Segment)
	}
	if len(resp.RankedPostIDs) != 3 {
		t.Errorf("후보 3 개를 기대했지만 %v", resp.RankedPostIDs)
	}
}

func TestSegmentHandlerResponse(t *testing.T) {
	rec := httptest.NewRecorder()

	segmentHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/segment?userId=3", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("200 을 기대했지만 %d", rec.Code)
	}
	var resp segmentResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("응답을 읽을 수 없습니다: %v", err)
	}
	if resp.UserID != 3 || resp.Segment != "beta" {
		t.Errorf("userId 3 은 beta 여야 하는데 %+v", resp)
	}
}

func TestSegmentHandlerRejectsInvalidUserID(t *testing.T) {
	for _, query := range []string{"", "?userId=", "?userId=abc", "?userId=0", "?userId=-1"} {
		rec := httptest.NewRecorder()

		segmentHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/segment"+query, nil))

		if rec.Code != http.StatusBadRequest {
			t.Errorf("%q: 400 을 기대했지만 %d", query, rec.Code)
		}
	}
}

func TestSegmentHandlerAgreesWithRankHandler(t *testing.T) {
	for _, userID := range []int64{1, 2, 3, 4, 6, 9, 100} {
		rec := httptest.NewRecorder()
		segmentHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/segment?userId="+strconv.FormatInt(userID, 10), nil))
		var lookup segmentResponse
		_ = json.Unmarshal(rec.Body.Bytes(), &lookup)

		body, _ := json.Marshal(rankRequest{UserID: userID, PostIDs: []int64{101}})
		rec = httptest.NewRecorder()
		rankHandler(testConfig).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/rank", bytes.NewReader(body)))
		var ranked rankResponse
		_ = json.Unmarshal(rec.Body.Bytes(), &ranked)

		if lookup.Segment != ranked.Segment {
			t.Errorf("userId %d: 조회는 %q 인데 랭킹은 %q", userID, lookup.Segment, ranked.Segment)
		}
	}
}

func TestRankHandlerRejectsMissingUserID(t *testing.T) {
	body, _ := json.Marshal(rankRequest{PostIDs: []int64{101}})
	rec := httptest.NewRecorder()

	rankHandler(testConfig).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/rank", bytes.NewReader(body)))

	if rec.Code != http.StatusBadRequest {
		t.Errorf("400 을 기대했지만 %d", rec.Code)
	}
}

func TestIncomingTraceparentIsContinued(t *testing.T) {
	otel.SetTextMapPropagator(propagation.TraceContext{})

	const incomingTraceID = "4bf92f3577b34da6a3ce929d0e0e4736"
	var seen trace.SpanContext
	handler := otelhttp.NewHandler(
		http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
			seen = trace.SpanContextFromContext(r.Context())
		}),
		"POST /v1/rank",
	)

	req := httptest.NewRequest(http.MethodPost, "/v1/rank", nil)
	req.Header.Set("traceparent", "00-"+incomingTraceID+"-00f067aa0ba902b7-01")
	handler.ServeHTTP(httptest.NewRecorder(), req)

	if got := seen.TraceID().String(); got != incomingTraceID {
		t.Errorf("들어온 traceId 를 이어받지 못했습니다: %q", got)
	}
}

func equal(a, b []int64) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
