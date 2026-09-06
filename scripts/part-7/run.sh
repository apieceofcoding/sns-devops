#!/usr/bin/env bash
# Phase 7. 트레이스
# 사용법: scripts/part-7/run.sh [lite|full]   (기본 lite)
set -euo pipefail
cd "$(dirname "$0")/../.."
PROFILE="${1:-lite}"

# JSON 을 보기 좋게 출력합니다. 윈도우에는 python3 라는 이름이 없는 경우가 많아
# jq, python3, python 순으로 있는 것을 쓰고, 셋 다 없으면 원문을 그대로 냅니다.
json_pp() {
    if command -v jq >/dev/null 2>&1; then jq .
    elif command -v python3 >/dev/null 2>&1; then python3 -m json.tool
    elif command -v python >/dev/null 2>&1; then python -m json.tool
    else cat
    fi
}

VALUES=(-f k8s/monitoring/tempo-values.yaml)
[ "$PROFILE" = full ] && VALUES+=(-f k8s/monitoring/tempo-values-full.yaml)

echo "==> 추천 서비스 빌드와 배포 (Go)"
docker build -t sns-recommender:latest apps/recommender
kind load docker-image sns-recommender:latest --name sns-cluster
kubectl apply -f k8s/sns-app/recommender.yaml
kubectl rollout status deployment/sns-recommender -n sns --timeout=120s

echo "==> Tempo 설치 ($PROFILE)"
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update grafana >/dev/null
helm upgrade --install tempo grafana/tempo \
    --namespace monitoring \
    --version 1.24.4 \
    "${VALUES[@]}"

echo "==> OTel Collector 갱신 (traces 파이프라인)"
helm upgrade otel-collector open-telemetry/opentelemetry-collector \
    --namespace monitoring \
    -f k8s/monitoring/otel-collector-values.yaml

echo "==> HTTPRoute 적용"
kubectl apply -f k8s/ingress/tempo.yaml

echo "==> 확인"
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=tempo -n monitoring --timeout=300s
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
echo
echo "==> 두 서비스에 걸친 트레이스 생성"
curl -fsS -o /dev/null "http://sns.localhost/api/v1/demo/trace?userId=1" 2>/dev/null || true
sleep 5

echo "==> sns-app 트레이스 확인"
curl -fsS "http://tempo.localhost/api/search?limit=5" | json_pp || true

echo "==> sns-recommender 트레이스 확인 (경계를 넘었는지)"
curl -fsS "http://tempo.localhost/api/search?tags=service.name%3Dsns-recommender&limit=5" | json_pp || true
