# 장애 대응 가이드

## 장애 대응 플로우

```
알림 수신 → 영향 범위 파악 → 원인 분석 → 조치 → 복구 확인 → 사후 분석
```

### 1단계: 영향 범위 파악 (2분 내)
- 어떤 서비스가 영향받는가?
- 사용자 영향 범위는? (전체 vs 일부)
- 언제부터 시작됐는가?

### 2단계: 원인 분석 (메트릭 기반)
- 최근 배포가 있었는가? → 롤백 검토
- 외부 의존성 장애인가? → 해당 서비스 상태 확인
- 리소스 부족인가? → CPU/Memory/Disk 확인
- 트래픽 급증인가? → 요청률 확인

### 3단계: 조치
- 배포 원인 → 즉시 롤백
- 리소스 부족 → 스케일 아웃
- 외부 의존성 → Circuit Breaker 확인, fallback 동작 확인
- 트래픽 급증 → Rate Limiting, 오토스케일링 확인

---

## 메트릭 기반 원인 분석 체크리스트

### 서비스 레벨 (RED)
| 증상 | 확인 메트릭 | 가능한 원인 |
|------|------------|------------|
| 에러율 급증 | http_requests_total{status=~"5.."} | 배포 버그, DB 연결 실패, 외부 API 장애 |
| 레이턴시 증가 | http_duration_seconds | DB 슬로우 쿼리, 외부 API 지연, GC pause |
| 요청률 급감 | http_requests_total | 업스트림 장애, DNS 문제, LB 설정 |
| 요청률 급증 | http_requests_total | DDoS, 크롤러, 재시도 폭풍 |

### 인프라 레벨 (USE)
| 증상 | 확인 메트릭 | 가능한 원인 |
|------|------------|------------|
| CPU 100% | node_cpu_seconds_total | 무한 루프, 과도한 연산, GC |
| Memory OOM | node_memory_MemAvailable_bytes | 메모리 누수, 캐시 과다 |
| Disk Full | node_filesystem_avail_bytes | 로그 폭증, 임시 파일 미정리 |
| Network 에러 | node_network_receive_errs_total | 패킷 손실, MTU 문제 |

### 데이터 레벨
| 증상 | 확인 메트릭 | 가능한 원인 |
|------|------------|------------|
| DB 연결 실패 | pg_stat_activity | max_connections 초과, 연결 누수 |
| 쿼리 느림 | pg_stat_statements | 인덱스 누락, lock 대기 |
| Kafka lag 증가 | kafka_consumer_group_lag | Consumer 처리 느림, 파티션 불균형 |
| ES 검색 느림 | es_search_latency | shard 과다, 복잡한 쿼리, GC |

---

## CloudWatch 기반 분석 절차

### 1. 활성 알람 확인
```
→ mcp_aws_cloudwatch_get_active_alarms
```

### 2. 알람 히스토리 (언제부터?)
```
→ mcp_aws_cloudwatch_get_alarm_history (alarm_name)
```

### 3. 관련 메트릭 조회
```
→ mcp_aws_cloudwatch_get_metric_data
  - namespace: AWS/EKS, AWS/RDS, AWS/Kafka 등
  - 시간 범위: 알람 발생 전후 1시간
```

### 4. 로그 분석
```
→ mcp_aws_cloudwatch_execute_log_insights_query
  - 에러 패턴 검색
  - 시간대별 에러 수 집계
```

### 5. 로그 그룹 이상 탐지
```
→ mcp_aws_cloudwatch_analyze_log_group
  - 자동 패턴 분석
  - anomaly 감지
```

---

## 일반적인 장애 시나리오별 대응

### 시나리오 1: 배포 후 에러 급증
```
1. 최근 배포 확인 (ArgoCD sync history)
2. 에러 로그에서 새로운 에러 패턴 확인
3. 이전 버전으로 롤백
4. 롤백 후 에러율 정상화 확인
5. 원인 분석 후 수정 배포
```

### 시나리오 2: DB 연결 고갈
```
1. pg_stat_activity에서 idle 연결 수 확인
2. 연결 누수 원인 (미반환 connection) 추적
3. 긴급: idle 연결 강제 종료
4. 근본: connection pool 설정 수정, 코드 수정
```

### 시나리오 3: Kafka Consumer Lag 급증
```
1. Consumer 인스턴스 상태 확인 (Pod 정상?)
2. 처리 시간 증가 원인 (외부 API? DB?)
3. 긴급: Consumer 인스턴스 추가
4. 근본: 처리 로직 최적화, 배치 크기 조정
```

### 시나리오 4: OOM Kill
```
1. Pod restart 이력 확인 (kubectl describe pod)
2. 메모리 사용 추이 확인 (Container Insights)
3. 힙 덤프 분석 (가능한 경우)
4. 긴급: memory limit 증가
5. 근본: 메모리 누수 수정
```

---

## 사후 분석 (Post-Mortem) 템플릿

```markdown
## 장애 요약
- 발생 시간: YYYY-MM-DD HH:MM ~ HH:MM (KST)
- 영향 범위: [서비스명], [사용자 수/비율]
- 심각도: P1/P2/P3

## 타임라인
- HH:MM - 알림 수신
- HH:MM - 원인 파악
- HH:MM - 조치 시작
- HH:MM - 복구 확인

## 근본 원인
[상세 설명]

## 조치 내용
[수행한 조치]

## 재발 방지
- [ ] 액션 아이템 1 (담당자, 기한)
- [ ] 액션 아이템 2 (담당자, 기한)

## 교훈
[배운 점]
```
