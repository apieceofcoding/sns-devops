# SNS 앱 모니터링 대시보드

## SNS App RED

[sns-app-red.json](./sns-app-red.json)은 SNS 앱의 상태를 세 그래프로 확인하는 Grafana 대시보드입니다.

| 패널 | 확인할 내용 | 단위 |
| --- | --- | --- |
| R: 초당 요청량 | 초당 몇 건의 요청을 처리하는지 | req/s |
| E: 5xx 오류율 | 전체 요청 중 HTTP 5xx 응답의 비율 | % |
| D: 평균 응답 시간 | 요청 하나를 처리하는 데 걸린 평균 시간 | ms |

최근 5분을 기준으로 계산하며, 30초마다 화면을 갱신해요. `namespace="sns"`, `service="sns-app"`인 메트릭을 사용하고, `/actuator/health`와 정확히 일치하는 요청만 제외합니다. 다른 Actuator 경로는 포함해요.

### Import

1. Grafana에서 **Dashboards → New → Import**로 이동합니다.
2. **Upload dashboard JSON file**에서 `sns-app-red.json`을 선택해요.
3. Prometheus 데이터소스를 선택하고 **Import**를 누릅니다.
4. SNS 앱의 API를 호출한 뒤 그래프를 확인해요. 처음에는 30초 수집 주기에 따라 샘플이 쌓일 시간이 필요합니다.

각 패널의 **Edit**에서 실제 PromQL을 확인할 수 있어요. 오류율은 4xx를 포함하지 않으며, 요청이 없으면 오류율과 평균 응답 시간은 표시하지 않습니다. 평균 응답 시간은 p95나 최대 응답 시간이 아니에요.

## 추천: JVM (Micrometer), 4701

[JVM (Micrometer) 대시보드](https://grafana.com/grafana/dashboards/4701-jvm-micrometer/)는 힙과 비힙 메모리, GC, CPU, 스레드 등 JVM 내부 상태를 살펴볼 때 유용합니다. RED 대시보드에서 서비스 상태를 보고, 이 대시보드로 JVM의 자원 상태를 함께 확인하면 좋아요.

Grafana의 **Import** 화면에서 대시보드 ID `4701`을 입력하고 **Load**한 뒤 Prometheus 데이터소스를 선택합니다. 이 폴더에 포함된 JSON은 RED 대시보드이며, 4701은 외부 대시보드를 별도로 가져오는 방식이에요.

### 필요한 앱 설정

4701은 메트릭의 `application` 라벨로 앱을 구분합니다. 현재 실습 앱에는 이 공통 라벨 설정이 없으므로, `sns-app`의 `application.yaml`에 있는 기존 `management` 아래에 `metrics` 설정을 병합하세요.

```yaml
management:
  metrics:
    tags:
      application: sns-app
```

기존 `management.health`와 `management.endpoints` 설정은 유지합니다. 앱을 빌드하고 재배포한 뒤 새 메트릭이 수집되면 대시보드에서 `application`을 `sns-app`으로 선택해요. 이 README를 추가하는 것만으로 앱 설정이 바뀌지는 않습니다.

### 호환성

실습 앱은 Spring Boot 4.1을 사용합니다. 4701의 모든 패널을 이 환경에서 검증한 것은 아니므로, 빈 패널은 메트릭 이름과 라벨을 확인하고 쿼리를 조정해야 할 수 있어요. 제작자 안내에 따르면 일부 프로세스 메모리 패널은 추가 라이브러리 `micrometer-jvm-extras`가 필요합니다. 이 라이브러리는 현재 실습에 추가하지 않았어요.

설정과 요구사항의 출처: [4701 제작자 안내](https://grafana.com/grafana/dashboards/4701-jvm-micrometer/).
