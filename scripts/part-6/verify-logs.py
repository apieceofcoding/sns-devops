#!/usr/bin/env python3
"""실행 중인 Collector와 Loki의 파일 수집을 검증합니다. Python 표준 라이브러리만 사용합니다."""
import json
import os
import subprocess
import time
import urllib.parse
import urllib.request
import uuid

name = "logcheck-" + uuid.uuid4().hex[:10]
namespace = os.environ.get("TEST_NAMESPACE", "sns")
loki = os.environ.get("LOKI_URL", "http://loki.localhost").rstrip("/")
trace_id = "0123456789abcdef0123456789abcdef"
span_id = "0123456789abcdef"
record = {
    "@timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
    "message": name + " structured",
    "level": "ERROR",
    "logger_name": "logcheck",
    "service_name": "sns-logcheck",
    "traceId": trace_id,
    "spanId": span_id,
    "stack_trace": "java.lang.IllegalStateException: test\n\tat example.Test.run(Test.java:1)",
}
startup = {k: v for k, v in record.items() if k not in ("traceId", "spanId", "stack_trace")}
startup.update(message=name + " startup", level="INFO")
# Collector가 파일을 발견한 뒤 로그를 쓰도록 잠시 기다립니다.
lines = [json.dumps(record), json.dumps(startup), name + " plain"]
pod = {
    "apiVersion": "v1", "kind": "Pod",
    "metadata": {"name": name, "namespace": namespace},
    "spec": {"restartPolicy": "Never", "containers": [{
        "name": "sns-app", "image": "busybox:1.37.0",
        "command": ["sh", "-c", 'sleep 15; printf "%s\\n" "$@"; sleep 90', "sh", *lines],
        "resources": {"requests": {"cpu": "10m", "memory": "16Mi"},
                      "limits": {"memory": "32Mi"}},
    }]},
}


def read_logs():
    query = urllib.parse.urlencode({
        "query": '{k8s_pod_name="' + name + '"}',
        "since": "10m", "limit": 100,
    })
    with urllib.request.urlopen(loki + "/loki/api/v1/query_range?" + query, timeout=10) as response:
        payload = json.load(response)
    return [(stream["stream"], value) for stream in payload["data"]["result"]
            for value in stream["values"]]


try:
    subprocess.run(["kubectl", "create", "-f", "-"], input=json.dumps(pod), text=True, check=True)
    subprocess.run(["kubectl", "wait", "-n", namespace, "pod/" + name,
                    "--for=condition=Ready", "--timeout=120s"], check=True)
    deadline = time.monotonic() + 100
    while True:
        logs = read_logs()
        if len(logs) >= 3:
            break
        if time.monotonic() > deadline:
            raise AssertionError("Loki에서 테스트 로그 3개를 찾지 못했습니다.")
        time.sleep(2)
    time.sleep(6)  # 다음 batch에서도 중복이 생기지 않는지 확인합니다.
    logs = read_logs()
    assert len(logs) == 3, f"로그 누락 또는 중복: {len(logs)}"
    by_body = {value[1]: {**labels, **(value[2] if len(value) > 2 else {})}
               for labels, value in logs}
    error = by_body[name + " structured"]
    assert error["service_name"] == "sns-logcheck", error
    assert error["severity_text"] == "ERROR", error
    assert error["trace_id"] == trace_id and error["span_id"] == span_id, error
    assert error["container_image_tag"] == "1.37.0", error
    assert error["exception_stacktrace"] == record["stack_trace"], error
    assert error["logger_name"] == "logcheck", error
    assert "trace_id" not in by_body[name + " startup"], by_body
    assert name + " plain" in by_body, by_body
    print("PASS: JSON, 일반 로그, 예외, 레벨, 이미지 태그, TraceID/SpanID, 중복 없음")
finally:
    subprocess.run(["kubectl", "delete", "pod", name, "-n", namespace,
                    "--ignore-not-found", "--wait=false"], check=False)
