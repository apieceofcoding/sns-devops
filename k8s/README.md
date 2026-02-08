# k8s/

Kind 클러스터 설정과 Kubernetes 매니페스트를 관리한다.

## 구조

```
k8s/
├── kind-config.yaml            # 일반 (control-plane + 2 workers)
├── kind-config-minimal.yaml    # 최소 (control-plane only)
└── springboot-sns/             # SNS 앱 매니페스트
```

## Kind 클러스터 생성

**일반 버전** (control-plane 1 + worker 2, 권장):

```bash
kind create cluster --config k8s/kind-config.yaml
```

**최소 버전** (메모리 16GB 이하이거나 Docker 리소스가 부족한 경우):

```bash
kind create cluster --config k8s/kind-config-minimal.yaml
```

> 두 설정 모두 클러스터명(`sns-cluster`)과 포트 매핑(`30080`)이 동일하므로 이후 과정은 동일하게 진행된다.

## 배포

```bash
# sns-app 이미지 빌드 & Kind에 로드
docker build -t springboot-sns:latest ../sns-app/
kind load docker-image springboot-sns:latest --name sns-cluster

# 매니페스트 적용 (namespace 먼저 생성)
kubectl apply -f k8s/springboot-sns/namespace.yaml
kubectl apply -f k8s/springboot-sns/

# 확인
kubectl get pods -n sns
curl -s localhost:30080/actuator/health | jq
```

## 정리

```bash
kind delete cluster --name sns-cluster
```
