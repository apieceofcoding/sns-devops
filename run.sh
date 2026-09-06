#!/usr/bin/env bash
# 이 브랜치의 단계 스크립트를 실행합니다.
# 이전 단계를 다시 돌리려면 scripts/part-2/run.sh 처럼 직접 실행하세요.
set -euo pipefail
exec "$(dirname "$0")/scripts/part-8/run.sh" "$@"
