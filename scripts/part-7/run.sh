#!/usr/bin/env bash
# Phase 7. 트레이스
# scripts/part-7 폴더에서 실행: ./run.sh [lite|full]   (기본 lite)
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/common.sh
require_files apps/recommender/Dockerfile \
    apps/recommender/go.mod \
    apps/recommender/go.sum \
    apps/recommender/main.go \
    k8s/sns-app/recommender.yaml \
    k8s/monitoring/tempo-values.yaml \
    k8s/monitoring/otel-collector-values.yaml \
    k8s/gateway/tempo.yaml
PROFILE="${1:-lite}"
require_profile "$PROFILE"
if [ "$PROFILE" = full ]; then require_files k8s/monitoring/tempo-values-full.yaml; fi

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
helm upgrade otel-collector open-telemetry/opentelemetry-collector --version 0.169.0 \
    --namespace monitoring \
    -f k8s/monitoring/otel-collector-values.yaml

echo "==> HTTPRoute 적용"
kubectl apply -f k8s/gateway/tempo.yaml

echo "==> 확인"
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=tempo -n monitoring --timeout=300s
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
echo
echo "sns-app을 07강 코드로 다시 배포한 뒤 sns-app/scripts/part-7/run.sh로 트레이스를 생성하세요."
