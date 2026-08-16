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

### 프로파일 선택

이 저장소는 두 가지 프로파일을 제공합니다. **기본은 lite** 입니다.

| | lite (기본) | full (강의 영상 기준) |
| --- | --- | --- |
| Docker Desktop 할당 메모리 | 4GB | 8GB |
| 노드 구성 | 단일 노드 | control-plane 1 + worker 2 |
| node-exporter | 없음 | 있음 |
| Grafana 기본 대시보드 | 없음 (커뮤니티 대시보드 직접 임포트) | 있음 |
| Tempo metrics-generator | 없음 | 있음 |
| 05강 이후 ArgoCD | 제거하고 진행 | 유지 |

강의 영상은 full 로 촬영했습니다. 노트북 메모리가 8GB 이하라면 lite 로 진행하세요.
실습 내용과 명령은 같고, 화면에 보이는 Pod 개수와 일부 선택 실습만 달라집니다.

**Docker Desktop 메모리 할당 확인**: Settings > Resources > Memory limit 에서
lite 는 4GB 이상, full 은 8GB 이상으로 설정하세요. 기본값 그대로 두면
06강 이후 Pod 이 `OOMKilled` 로 반복 재시작합니다.

아래 명령은 lite 기준입니다. `-full` 파일은 lite 와의 **차이만** 담고 있어서,
full 로 진행할 때는 기본 values 뒤에 이어서 붙입니다.

| | lite (기본) | full |
| --- | --- | --- |
| 클러스터 | `-f k8s/kind/kind-config.yaml` | `-f k8s/kind/kind-config-full.yaml` |
| Prometheus | `-f k8s/monitoring/kube-prometheus-values.yaml` | 왼쪽에 `-f k8s/monitoring/kube-prometheus-values-full.yaml` 추가 |
| Tempo | `-f k8s/monitoring/tempo-values.yaml` | 왼쪽에 `-f k8s/monitoring/tempo-values-full.yaml` 추가 |

나머지 values 파일은 두 프로파일이 공유합니다.

### 차트 버전

설치 명령에 버전을 고정해 두었습니다. 강의 영상과 같은 결과를 보려면 그대로 사용하세요.

| 차트 | 버전 | 앱 버전 |
| --- | --- | --- |
| Gateway API CRD | v1.6.1 (standard) | 해당 없음 |
| traefik/traefik | 41.2.0 | v3.7.10 |
| argo/argo-cd | 10.3.3 | v3.5.1 |
| prometheus-community/kube-prometheus-stack | 88.3.0 | v0.93.0 |
| grafana/loki | 7.3.0 | 3.6.12 |
| open-telemetry/opentelemetry-collector | 0.169.0 | 0.158.0 |
| grafana/tempo | 1.24.4 | 2.10.8 (values 에서 지정) |

## 2) 구조

```text
k8s/
├── kind/
│   ├── kind-config.yaml           # lite 기본 (control-plane only)
│   └── kind-config-full.yaml      # full (control-plane + 2 workers)
├── ingress/
│   ├── traefik-values.yaml        # Traefik Helm values (Gateway API provider)
│   ├── sns-app.yaml               # sns, rustfs HTTPRoute (02강)
│   ├── monitoring.yaml            # grafana, prometheus HTTPRoute (05강)
│   ├── loki.yaml                  # loki HTTPRoute (06강)
│   └── tempo.yaml                 # tempo HTTPRoute (07강)
├── argocd/
│   ├── argocd-values.yaml         # ArgoCD Helm values
│   └── application.yaml           # ArgoCD Application CRD
├── monitoring/
│   ├── alertrules.yaml            # PrometheusRule (에러율, 레이턴시, 다운)
│   ├── alertmanager-values.yaml   # AlertManager Slack 연동
│   ├── kube-prometheus-values.yaml       # lite 기본
│   ├── kube-prometheus-values-full.yaml  # full
│   ├── loki-values.yaml           # Loki Helm values (공통)
│   ├── otel-collector-values.yaml # OTel Collector Helm values (공통)
│   ├── tempo-values.yaml          # lite 기본
│   ├── tempo-values-full.yaml     # full
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
# lite (기본)
kind create cluster --config k8s/kind/kind-config.yaml

# full 로 진행한다면
# kind create cluster --config k8s/kind/kind-config-full.yaml

kubectl get nodes
```

lite 는 노드가 1개, full 은 3개로 보입니다.

삭제:

```bash
kind delete cluster --name sns-cluster
```

## 4) 설치 순서 (복붙용)

강의 진행 순서와 같습니다. lite 기준이고, full 은 표시된 곳에서 values 를 하나 더 붙입니다.

### 4-1. Gateway API CRD 와 Traefik (02강)

Gateway API 는 Kubernetes 코어에 포함되지 않은 CRD 라 먼저 설치해야 합니다.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
```

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik --version 41.2.0 -n traefik --create-namespace \
  -f k8s/ingress/traefik-values.yaml
```

차트가 `GatewayClass` 와 기본 `Gateway`(`traefik` 네임스페이스의 `traefik-gateway`)를
함께 만듭니다. 확인해 보세요.

```bash
kubectl get gatewayclass
kubectl get gateway -n traefik
```

`GatewayClass` 는 `ACCEPTED=True`, `Gateway` 는 `PROGRAMMED=True` 여야 합니다.

HTTPRoute 는 대상 네임스페이스가 만들어진 뒤에 적용합니다. 순서를 바꾸면
`namespaces "..." not found` 로 실패해요.

### 4-2. 애플리케이션 배포 (02강)

```bash
kubectl apply -f k8s/sns-app/namespace.yaml
kubectl apply -f k8s/sns-app/secret.yaml
kubectl apply -f k8s/sns-app/postgres.yaml \
  -f k8s/sns-app/redis.yaml \
  -f k8s/sns-app/rustfs.yaml
kubectl apply -f k8s/sns-app/app.yaml
kubectl apply -f k8s/ingress/sns-app.yaml
```

### 4-3. ArgoCD (04강)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd --version 10.3.3 -n argocd --create-namespace \
  -f k8s/argocd/argocd-values.yaml
kubectl apply -f k8s/argocd/application.yaml
```

lite 로 진행한다면 04강을 마친 뒤 여기서 ArgoCD 를 제거하고 다음 단계로 갑니다.
04강까지의 실습 결과는 Git 저장소에 남아 있고, 05강 이후에는 ArgoCD 가 필요하지 않습니다.

```bash
helm uninstall argocd -n argocd
kubectl delete namespace argocd
```

메모리를 500MB 가량 확보하는 것 외에 이유가 하나 더 있습니다. Application 이
`selfHeal: true` 라서, 켜둔 채로 08강의 `kubectl scale deployment sns-app --replicas=0` 을
실행하면 60초 안에 복제본이 자동 복구되어 장애 상황이 재현되지 않아요.

### 4-4. Prometheus + Grafana (05강)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack --version 88.3.0 \
  -n monitoring --create-namespace \
  -f k8s/monitoring/kube-prometheus-values.yaml

kubectl apply -f k8s/monitoring/servicemonitor.yaml
kubectl apply -f k8s/monitoring/alertrules.yaml
kubectl apply -f k8s/ingress/monitoring.yaml
```

full 은 마지막 `-f` 뒤에 `-f k8s/monitoring/kube-prometheus-values-full.yaml` 을 추가합니다.

### 4-5. Loki + OTel Collector + Tempo (06~07강)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install loki grafana/loki --version 7.3.0 -n monitoring \
  -f k8s/monitoring/loki-values.yaml

helm install otel-collector open-telemetry/opentelemetry-collector --version 0.169.0 \
  -n monitoring -f k8s/monitoring/otel-collector-values.yaml

helm install tempo grafana/tempo --version 1.24.4 -n monitoring \
  -f k8s/monitoring/tempo-values.yaml

kubectl apply -f k8s/ingress/loki.yaml
kubectl apply -f k8s/ingress/tempo.yaml
```

Tempo 를 full 로 진행하면 마지막 `-f` 뒤에 `-f k8s/monitoring/tempo-values-full.yaml` 을
추가합니다. metrics-generator 가 켜지고 Grafana Explore Traces 를 쓸 수 있어요.

### 4-6. AlertManager Slack 연동 (08강)

`slack-webhook` secret 을 만든 뒤 values 를 적용하세요.

```bash
kubectl create secret generic slack-webhook \
  -n monitoring \
  --from-literal=url='https://hooks.slack.com/services/xxx/yyy/zzz'

helm upgrade prometheus prometheus-community/kube-prometheus-stack --version 88.3.0 \
  -n monitoring --reuse-values -f k8s/monitoring/alertmanager-values.yaml
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
  - Traefik 이 아직 준비 중일 수 있음 (`kubectl get pods -n traefik`)
  - `Gateway` 상태 확인 (`kubectl get gateway -n traefik`, `PROGRAMMED=True` 여야 함)
  - `HTTPRoute` 상태 확인 (`kubectl describe httproute <이름> -n <네임스페이스>`,
    `Accepted` 와 `ResolvedRefs` 가 모두 True 여야 함)
  - 로컬 DNS/hosts 문제 시 `curl -H "Host: sns.localhost" http://127.0.0.1`
- `no matches for kind "HTTPRoute"` 오류
  - Gateway API CRD 미설치. 4-1 의 `kubectl apply` 를 먼저 실행하세요.
- ArgoCD 동기화 안 됨
  - `kubectl get applications -n argocd`
  - `repoURL/path` 오타 확인 (`k8s/argocd/application.yaml`)
- Prometheus가 `sns-app` 메트릭 미수집
  - `k8s/monitoring/servicemonitor.yaml` 적용 여부 확인
  - Helm 설치 시 `-f k8s/monitoring/kube-prometheus-values.yaml` 누락 여부 확인
- 로그가 중복 수집됨
  - `k8s/monitoring/otel-collector-values.yaml`의 file_log `exclude` 확인

## 8) 학습용 vs 실무용

이 저장소의 기본 설정은 학습/데모 최적화입니다.

- 학습용: 단일 바이너리 Loki/Tempo, 로컬 스토리지, 단순 secret
- 실무용: object storage, 백업/보존 정책, 외부 secret manager, TLS/mTLS, RBAC 최소권한

### Gateway 의 라우트 허용 범위

`traefik-values.yaml` 의 리스너는 `namespacePolicy.from: All` 입니다.
어느 네임스페이스에서든 이 Gateway 에 HTTPRoute 를 붙일 수 있다는 뜻이에요.
실습에서 `sns`, `rustfs`, `monitoring`, `argocd` 네 곳의 라우트를 추가 설정 없이
붙이려고 이렇게 두었습니다.

혼자 쓰는 로컬 클러스터라 문제가 없지만, 여러 팀이 함께 쓰는 클러스터라면
다른 팀이 우리 호스트명을 선점할 수 있습니다. 실무에서는 범위를 좁히세요.

```yaml
gateway:
  listeners:
    web:
      namespacePolicy:
        from: Selector
        selector:
          matchLabels:
            gateway-access: "true"
```

이렇게 두면 `gateway-access=true` 라벨이 붙은 네임스페이스만 라우트를 붙일 수 있어요.
