# Prometheus Rules & PromQL 레시피

## Recording Rules

### 기본 구조 (prometheus-rules.yaml)
```yaml
groups:
  - name: service_metrics
    interval: 30s
    rules:
      # HTTP 요청률 (5분 평균)
      - record: service:http_requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (service, method, status_code)

      # 에러율
      - record: service:http_error_rate:ratio5m
        expr: |
          sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (service)
          /
          sum(rate(http_requests_total[5m])) by (service)

      # P99 레이턴시
      - record: service:http_duration_seconds:p99_5m
        expr: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))

      # P50 레이턴시
      - record: service:http_duration_seconds:p50_5m
        expr: histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))
```

---

## Alerting Rules

### 서비스 알림 (RED Method)
```yaml
groups:
  - name: service_alerts
    rules:
      # 높은 에러율
      - alert: HighErrorRate
        expr: service:http_error_rate:ratio5m > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate on {{ $labels.service }}"
          description: "Error rate is {{ $value | humanizePercentage }} (threshold: 5%)"
          runbook_url: "https://wiki.example.com/runbooks/high-error-rate"

      # 높은 레이턴시
      - alert: HighLatencyP99
        expr: service:http_duration_seconds:p99_5m > 2
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High P99 latency on {{ $labels.service }}"
          description: "P99 latency is {{ $value }}s (threshold: 2s)"

      # 요청률 급감 (서비스 다운 의심)
      - alert: RequestRateDrop
        expr: |
          sum(rate(http_requests_total[5m])) by (service)
          < 0.1 * sum(rate(http_requests_total[1h] offset 1d)) by (service)
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Request rate dropped >90% on {{ $labels.service }}"
```

### 인프라 알림 (USE Method)
```yaml
groups:
  - name: infra_alerts
    rules:
      # CPU 사용률
      - alert: HighCPUUsage
        expr: |
          100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 15m
        labels:
          severity: warning

      # 메모리 사용률
      - alert: HighMemoryUsage
        expr: |
          (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
        for: 10m
        labels:
          severity: warning

      # 디스크 사용률
      - alert: DiskSpaceLow
        expr: |
          (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 85
        for: 5m
        labels:
          severity: critical

      # Pod 재시작
      - alert: PodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ $labels.pod }} is crash looping"
```

### Kafka 알림
```yaml
groups:
  - name: kafka_alerts
    rules:
      - alert: KafkaConsumerLagHigh
        expr: kafka_consumer_group_lag > 10000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Consumer group {{ $labels.group }} lag is {{ $value }}"

      - alert: KafkaUnderReplicatedPartitions
        expr: kafka_server_replicamanager_underreplicatedpartitions > 0
        for: 5m
        labels:
          severity: critical
```

---

## PromQL 레시피

### Rate & Increase
```promql
# 초당 요청 수 (5분 평균)
rate(http_requests_total[5m])

# 5분간 총 증가량
increase(http_requests_total[5m])

# irate: 마지막 2개 데이터포인트 기반 (스파이크 감지)
irate(http_requests_total[5m])
```

### 비율 계산
```promql
# 에러율 (%)
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100

# 가용률 (%)
1 - (sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])))
```

### Histogram Quantile
```promql
# P99
histogram_quantile(0.99, sum(rate(http_duration_bucket[5m])) by (le))

# P95 by service
histogram_quantile(0.95, sum(rate(http_duration_bucket[5m])) by (service, le))

# Apdex score (threshold: 0.5s)
(
  sum(rate(http_duration_bucket{le="0.5"}[5m]))
  + sum(rate(http_duration_bucket{le="2.0"}[5m]))
) / 2 / sum(rate(http_duration_count[5m]))
```

### Top-K
```promql
# 에러 가장 많은 상위 5개 엔드포인트
topk(5, sum(rate(http_requests_total{status=~"5.."}[5m])) by (path))
```

### 예측
```promql
# 4시간 후 디스크 풀 예측
predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0
```

---

## Severity 설계 기준

| Severity | 기준 | 대응 시간 | 알림 채널 |
|----------|------|-----------|-----------|
| critical | 서비스 중단, 데이터 유실 위험 | 즉시 (5분 내) | PagerDuty + Slack |
| warning | 성능 저하, 임계치 접근 | 업무 시간 내 | Slack |
| info | 참고 사항, 트렌드 변화 | 다음 점검 시 | 대시보드만 |
