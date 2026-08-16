#!/usr/bin/env bash
# Phase 3. CI/CD
# 사용법: ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 원격에서 최신 매니페스트 가져오기"
git pull --ff-only

echo "==> CI 가 갱신한 이미지 태그"
grep 'image:' k8s/sns-app/app.yaml

echo
echo "==> 갱신된 이미지로 재배포"
kubectl apply -f k8s/sns-app/app.yaml
kubectl rollout status deployment/sns-app -n sns --timeout=300s
kubectl get deployment sns-app -n sns \
    -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
