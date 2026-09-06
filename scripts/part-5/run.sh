#!/usr/bin/env bash
# Phase 5. 메트릭
# 사용법: scripts/part-5/run.sh [lite|full]   (기본 lite)
set -euo pipefail
cd "$(dirname "$0")/../.."
PROFILE="${1:-lite}"

VALUES=(-f k8s/monitoring/kube-prometheus-values.yaml)
[ "$PROFILE" = full ] && VALUES+=(-f k8s/monitoring/kube-prometheus-values-full.yaml)

echo "==> kube-prometheus-stack 설치 ($PROFILE)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring --create-namespace \
    --version 88.3.0 \
    "${VALUES[@]}"

echo "==> HTTPRoute 와 ServiceMonitor 적용"
kubectl apply -f k8s/ingress/monitoring.yaml
kubectl apply -f k8s/monitoring/servicemonitor.yaml

echo "==> 확인"
kubectl get pods -n monitoring
echo
echo "Grafana admin 비밀번호:"
kubectl get secret -n monitoring prometheus-grafana \
    -o jsonpath="{.data.admin-password}" | base64 -d; echo
echo "  http://grafana.localhost"
