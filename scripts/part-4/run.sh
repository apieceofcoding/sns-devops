#!/usr/bin/env bash
# Phase 4. GitOps 와 ArgoCD
# 사용법: scripts/part-4/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

echo "==> ArgoCD 설치"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd --version 10.3.3 \
    -n argocd -f k8s/argocd/argocd-values.yaml

echo "==> argocd-server 대기"
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd

echo "==> Application 등록"
kubectl apply -f k8s/argocd/application.yaml

echo "==> 확인"
kubectl get applications -n argocd
echo
echo "admin 비밀번호:"
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d; echo
