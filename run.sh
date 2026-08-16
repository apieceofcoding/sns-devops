#!/usr/bin/env bash
# Phase 9. AI Agent 기반 RCA
# 사용법: ./run.sh [분]   (기본 30)
set -euo pipefail
cd "$(dirname "$0")"
MINS="${1:-30}"

echo "==> 관측 스택 접속 확인"
for name in prometheus loki tempo; do
    if curl -fsS -o /dev/null --max-time 5 "http://$name.localhost" 2>/dev/null; then
        echo "  $name OK"
    else
        echo "  $name 접속 불가. HTTPRoute 와 /etc/hosts 를 확인하세요." >&2
    fi
done

echo
echo "==> RCA 시작점 수집 (최근 ${MINS}분)"
tools/obsctl rca sns-app "$MINS"

echo
echo "이제 Claude Code 에게 물어보세요."
echo "  \"sns-app 에러율이 올랐는데 원인 찾아줘\""
echo "rca 스킬이 이 CLI 로 세 신호를 이어서 원인을 좁힙니다."
