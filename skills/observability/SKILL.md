---
name: observability
description: |
  모니터링/로깅/알림 스택 가이드. Prometheus, Grafana, ELK(Elasticsearch+Logstash+Kibana),
  Filebeat, Fluentd, alerting rules, dashboard 패턴을 다룬다.
  트리거: Prometheus, Grafana, ELK, Kibana, Filebeat, Fluentd, 모니터링, 알림, 메트릭, 로깅, 대시보드, 알럿, 로그 수집, 추적, tracing, APM, 장애 감지
license: MIT
---

# Observability Stack

## 3 Pillars
- Metrics: 수치 데이터 (Prometheus)
- Logs: 이벤트 기록 (ELK/Loki)
- Traces: 요청 흐름 추적 (Jaeger/Tempo)

## Prometheus

### 메트릭 타입
- Counter: 단조 증가 (requests_total)
- Gauge: 증감 가능 (temperature, active_connections)
- Histogram: 분포 (request_duration_seconds)
- Summary: 분위수 (client-side 계산)

### PromQL 패턴
- Rate: rate(http_requests_total[5m])
- Error rate: rate(errors[5m]) / rate(requests[5m])
- P99 latency: histogram_quantile(0.99, rate(duration_bucket[5m]))

### Recording Rules
- 자주 쓰는 복잡한 쿼리를 미리 계산
- 대시보드 로딩 속도 개선

## Grafana Dashboard
- 서비스별 대시보드: RED method (Rate, Errors, Duration)
- 인프라 대시보드: USE method (Utilization, Saturation, Errors)
- 변수 활용: namespace, service, pod 드롭다운
- 알림 연동: Grafana Alerting → Slack/PagerDuty

## Alerting Rules
- Severity 분류: critical (즉시 대응), warning (확인 필요), info (참고)
- for 절: 일시적 스파이크 무시 (예: for: 5m)
- Runbook URL 포함: 알림에 대응 절차 링크

## ELK Stack

### 로그 수집 파이프라인
```
App → Filebeat → Logstash/Kafka → Elasticsearch → Kibana
```
또는:
```
App → Fluent Bit → Elasticsearch/S3
```

### 구조화된 로깅
- JSON 포맷 출력 (timestamp, level, message, context)
- correlation ID: 요청 추적용 (X-Request-Id)
- 민감 정보 마스킹 (PII, 토큰)

### Filebeat 설정
- 컨테이너 로그: /var/log/containers/*.log
- multiline 처리: 스택트레이스 합치기
- 프로세서: add_kubernetes_metadata

## 로그 레벨 전략
- ERROR: 즉시 대응 필요한 오류
- WARN: 잠재적 문제, 모니터링 필요
- INFO: 주요 비즈니스 이벤트
- DEBUG: 개발/디버깅용 (프로덕션에서는 OFF)

## 알림 설계 판단 기준
- 어떤 메트릭에 알림? → references/prometheus-rules.md
- 어떤 severity? → critical(서비스 중단), warning(성능 저하), info(트렌드)
- 대시보드 설계 → references/grafana-dashboards.md
- 로그 파이프라인 설정 → references/log-pipeline.md
- 장애 대응 절차 → references/troubleshooting.md

---

## MCP 연동

### 사용 MCP: aws-cloudwatch
- 상태: user-scope-config.md 참조
- 활용 도구:
  - `mcp_aws_cloudwatch_describe_log_groups` — 로그 그룹 목록
  - `mcp_aws_cloudwatch_execute_log_insights_query` — 로그 쿼리 실행
  - `mcp_aws_cloudwatch_analyze_log_group` — 로그 그룹 분석 (이상 탐지, 패턴)
  - `mcp_aws_cloudwatch_get_metric_data` — 메트릭 데이터 조회
  - `mcp_aws_cloudwatch_get_active_alarms` — 활성 알람 조회
  - `mcp_aws_cloudwatch_get_alarm_history` — 알람 히스토리
  - `mcp_aws_cloudwatch_analyze_metric` — 메트릭 분석 (추세, 계절성)
  - `mcp_aws_cloudwatch_get_recommended_metric_alarms` — 알람 추천

### 활용 시나리오
- "최근 에러 로그 보여줘" → execute_log_insights_query
- "CPU 사용률 추이 확인" → get_metric_data
- "현재 알람 상태" → get_active_alarms
- "이 로그 그룹 분석해줘" → analyze_log_group

### MCP 미연동 시
CloudWatch MCP가 연동되지 않은 경우:
1. "CloudWatch MCP가 연동되지 않았어. scope-manager 스킬로 설정할 수 있어." 안내
2. Prometheus/Grafana/ELK 설정 가이드는 MCP 없이도 제공 가능
3. AWS 메트릭/로그 직접 조회는 MCP 연동 필수
