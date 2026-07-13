# Grafana Dashboard 설계 가이드

## RED Method (서비스 대시보드)

### Rate (요청률)
```promql
# 전체 요청률
sum(rate(http_requests_total{service="$service"}[5m]))

# 상태코드별
sum(rate(http_requests_total{service="$service"}[5m])) by (status_code)

# 엔드포인트별
sum(rate(http_requests_total{service="$service"}[5m])) by (path)
```

### Errors (에러율)
```promql
# 에러율 (%)
sum(rate(http_requests_total{service="$service",status_code=~"5.."}[5m]))
/ sum(rate(http_requests_total{service="$service"}[5m])) * 100

# 에러 유형별
sum(rate(http_requests_total{service="$service",status_code=~"5.."}[5m])) by (status_code)
```

### Duration (레이턴시)
```promql
# P50, P90, P99 동시 표시
histogram_quantile(0.50, sum(rate(http_duration_bucket{service="$service"}[5m])) by (le))
histogram_quantile(0.90, sum(rate(http_duration_bucket{service="$service"}[5m])) by (le))
histogram_quantile(0.99, sum(rate(http_duration_bucket{service="$service"}[5m])) by (le))
```

---

## USE Method (인프라 대시보드)

### Utilization
```promql
# CPU 사용률
100 - avg(rate(node_cpu_seconds_total{mode="idle",instance="$instance"}[5m])) * 100

# 메모리 사용률
(1 - node_memory_MemAvailable_bytes{instance="$instance"} / node_memory_MemTotal_bytes{instance="$instance"}) * 100

# 디스크 사용률
(1 - node_filesystem_avail_bytes{instance="$instance",mountpoint="/"} / node_filesystem_size_bytes{instance="$instance",mountpoint="/"}) * 100
```

### Saturation
```promql
# CPU saturation (load average / CPU cores)
node_load1{instance="$instance"} / count(node_cpu_seconds_total{mode="idle",instance="$instance"})

# 디스크 I/O saturation
rate(node_disk_io_time_weighted_seconds_total{instance="$instance"}[5m])
```

### Errors
```promql
# 네트워크 에러
rate(node_network_receive_errs_total{instance="$instance"}[5m])
rate(node_network_transmit_errs_total{instance="$instance"}[5m])

# 디스크 에러
rate(node_disk_io_time_seconds_total{instance="$instance",device="sda"}[5m])
```

---

## Dashboard 변수 설정

```json
{
  "templating": {
    "list": [
      {
        "name": "namespace",
        "type": "query",
        "query": "label_values(kube_pod_info, namespace)",
        "refresh": 2
      },
      {
        "name": "service",
        "type": "query",
        "query": "label_values(http_requests_total{namespace=\"$namespace\"}, service)",
        "refresh": 2
      },
      {
        "name": "interval",
        "type": "interval",
        "options": [
          {"text": "1m", "value": "1m"},
          {"text": "5m", "value": "5m"},
          {"text": "15m", "value": "15m"}
        ]
      }
    ]
  }
}
```

---

## 패널 레이아웃 권장

### 서비스 대시보드 (1행 = 1 관심사)
```
Row 1: Overview
  [요청률 그래프] [에러율 Stat] [P99 Stat] [가용률 Gauge]

Row 2: Traffic
  [상태코드별 요청률] [엔드포인트별 요청률]

Row 3: Latency
  [P50/P90/P99 그래프] [레이턴시 히트맵]

Row 4: Errors
  [에러 유형별] [최근 에러 로그 테이블]

Row 5: Resources
  [CPU] [Memory] [Pod 수]
```

### Stat 패널 임계값
```json
{
  "thresholds": {
    "steps": [
      { "color": "green", "value": null },
      { "color": "yellow", "value": 1 },    // warning
      { "color": "red", "value": 5 }         // critical
    ]
  }
}
```

---

## 알림 설정 (Grafana Alerting)

### Contact Points
- Slack: #alerts-critical, #alerts-warning
- PagerDuty: critical만
- Email: 주간 리포트

### Notification Policy
```yaml
# 라우팅 규칙
routes:
  - match:
      severity: critical
    receiver: pagerduty+slack-critical
    group_wait: 30s
    repeat_interval: 5m
  - match:
      severity: warning
    receiver: slack-warning
    group_wait: 5m
    repeat_interval: 1h
  - match:
      severity: info
    receiver: slack-info
    group_wait: 30m
    repeat_interval: 12h
```

### Silence (유지보수 시)
- 배포 중: 해당 서비스 알림 30분 silence
- 계획된 점검: 전체 알림 silence (시간 지정)
