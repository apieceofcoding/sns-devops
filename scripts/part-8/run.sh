#!/usr/bin/env bash
# scripts/part-8 폴더에서 실행: ./run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/common.sh
require_files k8s/monitoring/alertmanager-values.yaml k8s/monitoring/alertrules.yaml
kubectl get secret slack-webhook -n monitoring >/dev/null

echo "==> Slack 설정과 경보 규칙 적용"
helm upgrade prometheus prometheus-community/kube-prometheus-stack --version 88.3.0 \
    -n monitoring --reuse-values -f k8s/monitoring/alertmanager-values.yaml
kubectl apply -f k8s/monitoring/alertrules.yaml

echo "http://prometheus.localhost/alerts 에서 규칙을 확인하세요."
echo "sns-app/scripts/part-8에서 ./run.sh rate, ./run.sh error, ./run.sh latency를 하나씩 실행해요."
