# sns-devops

배포와 관측 가능성 강의에서 Kubernetes 매니페스트와 Helm values를 작성하는 저장소입니다.
`main`에는 실습 안내, 전체 실행 스크립트와 빈 `k8s/` 디렉터리가 있어요. 배포 설정은 02강부터 직접 추가합니다.

## 실습 방식

이 저장소와 [sns-app](https://github.com/apieceofcoding/sns-app)을 자신의 GitHub 계정으로 Fork하고 나란히 clone하세요.
수강생은 두 저장소의 `main`에서 변경을 커밋하며 끝까지 진행합니다.

| 브랜치 | 용도 |
| --- | --- |
| `main` | 실습 시작 골격과 전체 실행 스크립트. 자신의 Fork에서 배포 설정을 누적해요. |
| `part-2-kind-deployment` ~ `part-9-ai-agent-analysis` | 각 강의까지 완료한 코드 |
| `backup/main` | 실습 시작 상태로 바꾸기 전의 기존 `main` 백업 |

완료본은 강사 저장소의 `part-*`에서 확인할 수 있습니다.
처음부터 실습한다면 `main`에서 작업을 이어가고, 정답을 비교하거나 중간부터 시작할 때 완료본을 참고하세요.

## 시작 상태

```text
sns-devops/
├── README.md
├── scripts/
│   ├── README.md
│   ├── common.sh
│   ├── part-2/run.sh
│   ├── ...
│   └── part-9/run.sh
└── k8s/
    └── .gitkeep
```

`.gitkeep`은 빈 디렉터리를 Git에 보관하기 위한 파일이에요.
01강에서는 `sns-app`만 실행합니다. 이 저장소에는 실행 스크립트가 준비되어 있고, 매니페스트는 02강부터 작성해요.

02강부터 Docker, `kind`, `kubectl`, `helm`을 준비하고 다음 설정을 작성해요.

| 단계 | 추가할 내용 |
| --- | --- |
| 02 | `k8s/kind/`, `k8s/ingress/`, `k8s/sns-app/` |
| 03 | CI가 `k8s/sns-app/app.yaml`의 이미지 태그를 갱신하도록 연결 |
| 04 | `k8s/argocd/` |
| 05 ~ 08 | `k8s/monitoring/`, 추천 서비스, 로그와 트레이스, 경보 설정 |
| 09 | 장애 분석 도구와 대응 절차 |

## 제공된 실행 스크립트

`main`에는 02강부터 09강까지의 `scripts/`가 모두 들어 있습니다.
해당 단원의 매니페스트와 values를 작성한 뒤 폴더로 들어가 실행하세요.

```bash
# sns-devops 폴더에서 실행
cd scripts/part-2
./run.sh
```

단원별 명령과 프로파일 선택은 [scripts/README.md](scripts/README.md)에 정리했습니다.
필요한 설정 파일이 없으면 배포 전에 안내하고 종료해요.

## CI와 GitOps 연결

03강과 04강에서는 다음 흐름으로 설정합니다.

```text
내 sns-app/main에 push
  → GitHub Actions에서 이미지 발행
  → 내 sns-devops/main의 이미지 태그 갱신
  → Argo CD가 main의 변경을 감지해 Kind에 배포
```

CI가 수정할 저장소와 Argo CD가 감시할 저장소는 모두 자신의 `sns-devops`로 지정하세요.
CI의 checkout에는 `ref: main`, Argo CD에는 `targetRevision: main`을 명시합니다.
강의가 바뀌어도 이 연결은 유지해요.
