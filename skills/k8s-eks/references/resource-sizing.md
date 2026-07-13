# 리소스 사이징 가이드

## Requests / Limits 설정 원칙

### CPU
```yaml
resources:
  requests:
    cpu: "250m"      # 스케줄링 보장량 (0.25 core)
  limits:
    cpu: "1000m"     # 최대 사용량 (1 core) — throttle됨 (OOM 아님)
```
- requests = 평균 사용량의 1.2~1.5배
- limits = 피크 사용량 (또는 설정하지 않음 — burstable)
- CPU limit 미설정 권장론: throttling이 레이턴시 스파이크 유발

### Memory
```yaml
resources:
  requests:
    memory: "256Mi"   # 스케줄링 보장량
  limits:
    memory: "512Mi"   # 초과 시 OOM Kill!
```
- requests ≈ limits (메모리는 반환 안 되므로)
- limits = 정상 운영 최대값 + 20% 여유
- OOM Kill 방지: limits를 넉넉히, 단 노드 메모리 고려

---

## 워크로드별 권장 사이징

### API 서버 (Node.js/Java)
```yaml
# Node.js (단일 스레드, 메모리 효율적)
resources:
  requests: { cpu: "100m", memory: "128Mi" }
  limits: { cpu: "500m", memory: "256Mi" }

# Java (JVM 힙 + 메타스페이스)
resources:
  requests: { cpu: "500m", memory: "512Mi" }
  limits: { cpu: "2000m", memory: "1Gi" }
# JVM 옵션: -XX:MaxRAMPercentage=75 (limits의 75%를 힙으로)
```

### Worker (배치/큐 처리)
```yaml
resources:
  requests: { cpu: "250m", memory: "256Mi" }
  limits: { cpu: "1000m", memory: "512Mi" }
```

### Kafka Consumer
```yaml
resources:
  requests: { cpu: "200m", memory: "256Mi" }
  limits: { cpu: "1000m", memory: "512Mi" }
```

---

## VPA (Vertical Pod Autoscaler)

### 설정
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: api-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-server
  updatePolicy:
    updateMode: "Off"  # 권장: Off (추천만 받고 수동 적용)
  resourcePolicy:
    containerPolicies:
      - containerName: api
        minAllowed:
          cpu: "50m"
          memory: "64Mi"
        maxAllowed:
          cpu: "2000m"
          memory: "2Gi"
```

### VPA 추천 확인
```bash
kubectl describe vpa api-vpa
# Status.Recommendation.ContainerRecommendations 확인
```

### VPA vs HPA
| | VPA | HPA |
|--|-----|-----|
| 방향 | 수직 (리소스 증가) | 수평 (Pod 수 증가) |
| 재시작 | 필요 (Pod 재생성) | 불필요 |
| 용도 | 적정 리소스 찾기 | 트래픽 대응 |
| 동시 사용 | CPU는 HPA, Memory는 VPA |

---

## QoS 클래스

| 클래스 | 조건 | OOM 우선순위 |
|--------|------|:---:|
| Guaranteed | requests = limits (모든 컨테이너) | 마지막 (가장 안전) |
| Burstable | requests < limits | 중간 |
| BestEffort | requests/limits 미설정 | 첫 번째 (가장 위험) |

### 권장
- 프로덕션 중요 서비스: Guaranteed 또는 Burstable (requests 충분히)
- 배치/크론잡: Burstable
- 개발 환경: BestEffort 허용

---

## LimitRange / ResourceQuota

### Namespace별 기본값 (LimitRange)
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
    - type: Container
      default:
        cpu: "500m"
        memory: "256Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      max:
        cpu: "4000m"
        memory: "4Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
```

### Namespace별 총량 제한 (ResourceQuota)
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-analytics
spec:
  hard:
    requests.cpu: "20"
    requests.memory: "40Gi"
    limits.cpu: "40"
    limits.memory: "80Gi"
    pods: "50"
```

---

## 사이징 프로세스

1. **초기**: 보수적으로 설정 (넉넉하게)
2. **관찰**: 1~2주 실제 사용량 모니터링 (Container Insights)
3. **조정**: VPA 추천 참고하여 requests/limits 조정
4. **반복**: 트래픽 패턴 변화 시 재조정

### 모니터링 쿼리 (Prometheus)
```promql
# 실제 CPU 사용 vs requests
container_cpu_usage_seconds_total / container_spec_cpu_quota

# 실제 Memory 사용 vs limits
container_memory_working_set_bytes / container_spec_memory_limit_bytes

# Over-provisioned Pods (requests 대비 실제 사용 < 50%)
container_memory_working_set_bytes / kube_pod_container_resource_requests{resource="memory"} < 0.5
```
