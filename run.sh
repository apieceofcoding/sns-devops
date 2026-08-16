#!/usr/bin/env bash
# Phase 7. 트레이스
# 사용법: ./run.sh [lite|full]   (기본 lite)
set -euo pipefail
cd "$(dirname "$0")"
PROFILE="${1:-lite}"

VALUES=(-f k8s/monitoring/tempo-values.yaml)
[ "$PROFILE" = full ] && VALUES+=(-f k8s/monitoring/tempo-values-full.yaml)

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
curl -fsS -o /dev/null http://sns.localhost/api/v1/demo/trace 2>/dev/null || true
sleep 5
curl -fsS "http://tempo.localhost/api/search?limit=5" | python3 -m json.tool || true
