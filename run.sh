#!/usr/bin/env bash
# Phase 2. kind 배포
# 사용법: ./run.sh [lite|full]   (기본 lite)
set -euo pipefail
cd "$(dirname "$0")"
PROFILE="${1:-lite}"
CLUSTER=sns-cluster

if ! docker image inspect springboot-sns:latest >/dev/null 2>&1; then
    echo "springboot-sns:latest 이미지가 없습니다." >&2
    echo "먼저 sns-app 에서 실행하세요: git -C ../sns-app checkout part-2-kind-deployment && (cd ../sns-app && ./run.sh)" >&2
    exit 1
fi

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    echo "==> 클러스터 $CLUSTER 이미 존재, 생성 건너뜀"
else
    echo "==> 클러스터 생성 ($PROFILE)"
    if [ "$PROFILE" = full ]; then
        kind create cluster --config k8s/kind/kind-config-full.yaml
    else
        kind create cluster --config k8s/kind/kind-config.yaml
    fi
fi

echo "==> 이미지 적재"
kind load docker-image springboot-sns:latest --name "$CLUSTER"

echo "==> Gateway API CRD 설치"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml

echo "==> Traefik 설치"
helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo update traefik >/dev/null
helm upgrade --install traefik traefik/traefik --version 41.2.0 \
    --namespace traefik --create-namespace \
    --values k8s/ingress/traefik-values.yaml

echo "==> 매니페스트 적용"
kubectl apply -f k8s/sns-app/namespace.yaml
kubectl apply -f k8s/sns-app/secret.yaml
kubectl apply -f k8s/sns-app/postgres.yaml \
    -f k8s/sns-app/redis.yaml \
    -f k8s/sns-app/rustfs.yaml
kubectl apply -f k8s/sns-app/app.yaml
kubectl apply -f k8s/ingress/sns-app.yaml

echo "==> 롤아웃 대기"
kubectl rollout status deployment/sns-app -n sns --timeout=300s

echo "==> 확인"
kubectl wait --for=condition=Ready pod -l app=sns-app -n sns --timeout=180s
kubectl get pods -n sns
curl -fsS http://sns.localhost/actuator/health; echo
