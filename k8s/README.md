# k8s/

Kind 클러스터 설정, Kubernetes 매니페스트, Helm values를 관리합니다.
학습자 기준으로 "복붙 가능한 실행 순서 + 검증 포인트"를 먼저 제공합니다.

## 1) 사전 준비

- Docker Desktop
- `kubectl`
- `kind`
- `helm`

확인 명령:

```bash
docker --version
kubectl version --client
kind version
helm version
```

## 2) 구조

```text
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
    └── app.yaml
```

## 3) 클러스터 생성/삭제

```bash
kind create cluster --config k8s/kind/kind-config.yaml
kubectl get nodes
```

삭제:

```bash
kind delete cluster --name sns-cluster
```

## 4) 설치 순서 (복붙용)

### 4-1. Traefik + Ingress

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik -n traefik --create-namespace \
  -f k8s/ingress/traefik-values.yaml

kubectl apply -f k8s/ingress/monitoring.yaml
kubectl apply -f k8s/ingress/sns-app.yaml
```

### 4-2. ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd --version 9.4.1 -n argocd --create-namespace \
  -f k8s/argocd/argocd-values.yaml
kubectl apply -f k8s/argocd/application.yaml
```

### 4-3. Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.enableRemoteWriteReceiver=true

kubectl apply -f k8s/monitoring/servicemonitor.yaml
kubectl apply -f k8s/monitoring/alertrules.yaml
```

### 4-4. Loki + OTel Collector + Tempo

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install loki grafana/loki -n monitoring -f k8s/monitoring/loki-values.yaml

helm install otel-collector open-telemetry/opentelemetry-collector -n monitoring \
  -f k8s/monitoring/otel-collector-values.yaml

helm install tempo grafana/tempo -n monitoring -f k8s/monitoring/tempo-values.yaml
```

### 4-5. AlertManager Slack 연동

`slack-webhook` secret을 만든 뒤 values를 적용하세요.

```bash
kubectl create secret generic slack-webhook \
  -n monitoring \
  --from-literal=url='https://hooks.slack.com/services/xxx/yyy/zzz'

helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring \
  --reuse-values -f k8s/monitoring/alertmanager-values.yaml
```

## 5) 접속 URL

- SNS App: `http://sns.localhost`
- ArgoCD: `http://argocd.localhost`
- Grafana: `http://grafana.localhost`
- Prometheus: `http://prometheus.localhost`
- Loki: `http://loki.localhost`
- Tempo: `http://tempo.localhost`

## 6) 검증 체크리스트

1. `kubectl get nodes` -> 모두 `Ready`
2. `kubectl get pods -A` -> 주요 Pod `Running`
3. `curl http://sns.localhost/actuator/health` -> `UP`
4. Grafana Explore에서 Loki 로그 조회 가능
5. Grafana Explore에서 Tempo trace 조회 가능

## 7) 자주 막히는 문제

- `*.localhost` 접속 안 됨
  - Ingress가 아직 준비 중일 수 있음 (`kubectl get pods -n traefik`)
  - 로컬 DNS/hosts 문제 시 `curl -H "Host: sns.localhost" http://127.0.0.1`
- ArgoCD 동기화 안 됨
  - `kubectl get applications -n argocd`
  - `repoURL/path` 오타 확인 (`k8s/argocd/application.yaml`)
- Prometheus가 `sns-app` 메트릭 미수집
  - `k8s/monitoring/servicemonitor.yaml` 적용 여부 확인
  - Helm 설치 시 `serviceMonitorSelectorNilUsesHelmValues=false` 누락 여부 확인
- 로그가 중복 수집됨
  - `k8s/monitoring/otel-collector-values.yaml`의 filelog `exclude` 확인

## 8) 학습용 vs 실무용

이 저장소의 기본 설정은 학습/데모 최적화입니다.

- 학습용: 단일 바이너리 Loki/Tempo, 로컬 스토리지, 단순 secret
- 실무용: object storage, 백업/보존 정책, 외부 secret manager, TLS/mTLS, RBAC 최소권한
