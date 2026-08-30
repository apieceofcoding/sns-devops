#!/usr/bin/env bash
# Phase 8. 알림과 장애 대응
# 사용법: ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "==> AlertManager 설정 반영"
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --reuse-values \
    -f k8s/monitoring/alertmanager-values.yaml

echo "==> 알림 규칙 적용"
kubectl apply -f k8s/monitoring/alertrules.yaml

echo "==> 규칙 등록 확인"
sleep 10
curl -fsS "http://prometheus.localhost/api/v1/rules?type=alert" | python3 -m json.tool | head -30 || true

echo
echo "알림을 실제로 띄우려면 sns-app 에서 ./run.sh 로 에러 트래픽을 발생시키세요."
echo "  git -C ../sns-app checkout part-8-alerting-incident-response && (cd ../sns-app && ./run.sh)"
