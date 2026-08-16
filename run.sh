#!/usr/bin/env bash
# Phase 6. 로그
# 사용법: ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Loki 설치"
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update grafana >/dev/null
helm upgrade --install loki grafana/loki \
    --namespace monitoring \
    --version 7.3.0 \
    -f k8s/monitoring/loki-values.yaml

echo "==> OTel Collector 설치"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry >/dev/null
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
    --namespace monitoring \
    --version 0.169.0 \
    -f k8s/monitoring/otel-collector-values.yaml

echo "==> HTTPRoute 적용"
kubectl apply -f k8s/ingress/loki.yaml

echo "==> 확인"
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=loki -n monitoring --timeout=300s
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector
echo
curl -fsS http://loki.localhost/loki/api/v1/labels | python3 -m json.tool || true
