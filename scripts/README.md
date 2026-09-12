# 실습 스크립트

`main`에서 단원의 설정을 작성한 뒤, 해당 폴더에서 `./run.sh`를 실행하세요.
스크립트는 이미 제공되어 있으므로 직접 작성하지 않아도 됩니다.

```bash
# sns-devops 폴더에서 02강 실행
cd scripts/part-2
./run.sh

# full 프로파일을 선택했다면 위 명령 대신 실행
# ./run.sh full

# 다음 단원으로 이동
cd ../part-3
./run.sh
```

| 폴더 | 실행 명령 | 하는 일 |
| --- | --- | --- |
| `part-2` | `./run.sh` | Kind 배포 |
| `part-3` | `./run.sh` | CI가 갱신한 매니페스트를 받아 배포 |
| `part-4` | `./run.sh` | Argo CD 설치 |
| `part-5` | `./run.sh` | Prometheus와 Grafana 설치 |
| `part-6` | `./run.sh` | Loki와 Collector 설치 |
| `part-7` | `./run.sh` | 추천 서비스와 Tempo 배포 |
| `part-8` | `./run.sh` | 경보 설정 적용 |
| `part-9` | `./run.sh 30` | 최근 30분 장애 분석 |

02강, 05강, 07강에서 full을 쓰려면 `./run.sh full`로 실행해요. 생략하면 lite입니다.
이전 단원까지의 환경이 필요합니다. 02강 실행 전에는 `sns-app`의 02강 스크립트로 이미지를 먼저 빌드하세요.
