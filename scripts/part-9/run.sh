#!/usr/bin/env bash
# Phase 9. AI Agent 기반 장애 분석
# 사용법: scripts/part-9/run.sh [분]   (기본 30)
set -euo pipefail
cd "$(dirname "$0")/../.."
MINS="${1:-30}"

# 윈도우는 *.localhost 를 자동으로 127.0.0.1 로 풀지 않습니다. 안 될 때 안내할 위치를 고릅니다.
hosts_hint() {
    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*) file='C:\Windows\System32\drivers\etc\hosts (관리자 권한)' ;;
        *) file='/etc/hosts (sudo)' ;;
    esac
    echo "  이름이 풀리지 않으면 $file 에 아래 줄을 추가하세요." >&2
    echo "  127.0.0.1 sns.localhost grafana.localhost prometheus.localhost loki.localhost tempo.localhost argocd.localhost" >&2
}

echo "==> 관측 스택 접속 확인"
unreachable=0
for name in prometheus loki tempo; do
    if curl -fsS -o /dev/null --max-time 5 "http://$name.localhost" 2>/dev/null; then
        echo "  $name OK"
    else
        echo "  $name 접속 불가. HTTPRoute 를 확인하세요." >&2
        unreachable=$((unreachable+1))
    fi
done
if [ "$unreachable" -gt 0 ]; then
    hosts_hint
fi

echo
echo "==> 추천 서비스 확인 (beta 세그먼트 실패의 상대편입니다)"
if kubectl get deployment sns-recommender -n sns >/dev/null 2>&1; then
    kubectl rollout status deployment/sns-recommender -n sns --timeout=60s
else
    echo "  sns-recommender 가 없습니다. scripts/part-7/run.sh 를 먼저 실행하세요." >&2
fi

echo
echo "==> 장애 분석 시작점 수집 (최근 ${MINS}분)"
tools/obsctl analyze sns-app "$MINS"

echo
echo "이제 Claude Code 에게 물어보세요."
echo "  \"sns-app 에러율이 올랐는데 원인 찾아줘\""
echo "장애 분석 스킬이 이 CLI 로 세 신호를 이어서 원인을 좁힙니다."
