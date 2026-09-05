#!/usr/bin/env bash
# Phase 8. 알림과 장애 대응
# 사용법: ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

# JSON 을 보기 좋게 출력합니다. 윈도우에는 python3 라는 이름이 없는 경우가 많아
# jq, python3, python 순으로 있는 것을 쓰고, 셋 다 없으면 원문을 그대로 냅니다.
json_pp() {
    if command -v jq >/dev/null 2>&1; then jq .
    elif command -v python3 >/dev/null 2>&1; then python3 -m json.tool
    elif command -v python >/dev/null 2>&1; then python -m json.tool
    else cat
    fi
}

echo "==> AlertManager 설정 반영"
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --reuse-values \
    -f k8s/monitoring/alertmanager-values.yaml

echo "==> 알림 규칙 적용"
kubectl apply -f k8s/monitoring/alertrules.yaml

echo "==> 규칙 등록 확인"
sleep 10
# head 로 파이프하면 앞쪽 명령이 SIGPIPE 로 죽어 pipefail 이 실패로 판정합니다.
# 먼저 변수에 받아 두고 히어스트링으로 잘라 씁니다.
if rules=$(curl -fsS "http://prometheus.localhost/api/v1/rules?type=alert"); then
    head -30 <<<"$(json_pp <<<"$rules")"
else
    echo "  prometheus.localhost 에서 알림 규칙을 읽지 못했습니다." >&2
fi

echo
echo "알림을 실제로 띄우려면 sns-app 에서 ./run.sh 로 에러 트래픽을 발생시키세요."
echo "  git -C ../sns-app checkout part-8-alerting-incident-response && (cd ../sns-app && ./run.sh)"
