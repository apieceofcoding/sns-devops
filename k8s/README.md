# k8s/

Kind 클러스터 설정, Kubernetes 매니페스트, Helm values를 관리한다.

## 구조

```
k8s/
├── kind/
│   ├── kind-config.yaml           # 일반 (control-plane + 2 workers)
│   └── kind-config-minimal.yaml   # 최소 (control-plane only)
├── ingress/
│   ├── traefik-values.yaml        # Traefik Helm values
│   ├── monitoring.yaml            # grafana/prometheus/loki/tempo.localhost
│   └── sns-app.yaml               # sns.localhost
├── argocd/
│   ├── argocd-values.yaml         # ArgoCD Helm values
│   └── application.yaml           # ArgoCD Application CRD
├── monitoring/
│   ├── alertrules.yaml            # PrometheusRule (에러율, 레이턴시, 다운)
│   ├── alertmanager-values.yaml   # AlertManager Slack 연동
│   ├── loki-values.yaml           # Loki Helm values
│   ├── otel-collector-values.yaml # OTel Collector Helm values
│   ├── tempo-values.yaml          # Tempo Helm values
│   └── servicemonitor.yaml        # sns-app ServiceMonitor
└── sns-app/
    ├── namespace.yaml
    ├── secret.yaml
    ├── postgres.yaml
    ├── redis.yaml
    ├── rustfs.yaml
    └── app.yaml                   # Deployment + Service (ClusterIP)
```

## 클러스터 생성

```bash
kind create cluster --config k8s/kind/kind-config.yaml
```

## Helm 설치 순서

```bash
# 1. Traefik (Ingress Controller)
helm install traefik traefik/traefik -n traefik --create-namespace \
  -f k8s/ingress/traefik-values.yaml

# 2. Ingress 리소스
kubectl apply -f k8s/ingress/monitoring.yaml
kubectl apply -f k8s/ingress/sns-app.yaml

# 3. ArgoCD
helm install argocd argo/argo-cd --version 9.4.1 -n argocd --create-namespace \
  -f k8s/argocd/argocd-values.yaml
kubectl apply -f k8s/argocd/application.yaml

# 4. Prometheus + Grafana
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.enableRemoteWriteReceiver=true
kubectl apply -f k8s/monitoring/servicemonitor.yaml
kubectl apply -f k8s/monitoring/alertrules.yaml

# 5. Loki
helm install loki grafana/loki -n monitoring -f k8s/monitoring/loki-values.yaml

# 6. OTel Collector
helm install otel-collector open-telemetry/opentelemetry-collector -n monitoring \
  -f k8s/monitoring/otel-collector-values.yaml

# 7. Tempo
helm install tempo grafana/tempo -n monitoring -f k8s/monitoring/tempo-values.yaml

# 8. AlertManager Slack 연동
helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring \
  --reuse-values -f k8s/monitoring/alertmanager-values.yaml
```

## 접속

| 서비스 | URL |
|--------|-----|
| SNS App | http://sns.localhost |
| ArgoCD | http://argocd.localhost |
| Grafana | http://grafana.localhost |
| Prometheus | http://prometheus.localhost |
| Loki | http://loki.localhost |
| Tempo | http://tempo.localhost |
