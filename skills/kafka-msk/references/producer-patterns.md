# Producer 패턴 상세

## 배치 최적화

### 핵심 설정
```properties
# 처리량 우선 (높은 throughput)
batch.size=65536            # 배치 크기 (bytes), 기본 16384
linger.ms=20               # 배치 대기 시간 (ms), 기본 0
compression.type=lz4       # 압축 (none, gzip, snappy, lz4, zstd)
buffer.memory=67108864     # 전체 버퍼 메모리 (64MB)

# 지연 우선 (낮은 latency)
batch.size=16384
linger.ms=0                # 즉시 전송
compression.type=none
```

### 처리량 vs 지연 트레이드오프
| 설정 | 높은 처리량 | 낮은 지연 |
|------|:---------:|:--------:|
| batch.size | 64KB+ | 16KB |
| linger.ms | 10~50ms | 0 |
| compression | lz4/zstd | none |
| acks | 1 | 1 |

---

## 에러 핸들링

### Retriable vs Non-Retriable 에러
| 에러 | Retriable | 대응 |
|------|:---------:|------|
| NetworkException | ✅ | 자동 재시도 |
| LeaderNotAvailableException | ✅ | 자동 재시도 |
| NotEnoughReplicasException | ✅ | 자동 재시도 |
| RecordTooLargeException | ❌ | DLQ로 라우팅 |
| SerializationException | ❌ | 로깅 + 스킵 |
| AuthorizationException | ❌ | 설정 수정 필요 |

### 재시도 설정
```properties
retries=2147483647          # 무한 재시도 (delivery.timeout.ms로 제한)
delivery.timeout.ms=120000  # 최대 2분 내 전달
retry.backoff.ms=100        # 재시도 간격
```

### Callback 패턴 (Java)
```java
producer.send(record, (metadata, exception) -> {
    if (exception != null) {
        if (exception instanceof RetriableException) {
            // 자동 재시도됨, 로깅만
            log.warn("Retriable error, will retry: {}", exception.getMessage());
        } else {
            // Non-retriable: DLQ로 전송
            dlqProducer.send(new ProducerRecord<>("topic.DLQ", record.key(), record.value()));
            log.error("Non-retriable error: {}", exception.getMessage());
        }
    }
});
```

---

## Idempotent Producer

```properties
enable.idempotence=true     # 중복 방지 (PID + sequence number)
acks=all                    # 자동 설정됨
max.in.flight.requests.per.connection=5  # 최대 5 (idempotent 모드)
```

동작 원리:
1. Producer에 고유 PID (Producer ID) 할당
2. 각 파티션별 sequence number 부여
3. Broker가 중복 감지 → 중복 메시지 무시

---

## Transactional Producer

```java
Properties props = new Properties();
props.put("transactional.id", "order-service-1");  // 고유 ID (인스턴스별)
props.put("enable.idempotence", "true");

KafkaProducer<String, String> producer = new KafkaProducer<>(props);
producer.initTransactions();

try {
    producer.beginTransaction();
    producer.send(new ProducerRecord<>("orders", key, value));
    producer.send(new ProducerRecord<>("notifications", key, notification));
    producer.commitTransaction();
} catch (ProducerFencedException | OutOfOrderSequenceException e) {
    producer.close();  // 복구 불가
} catch (KafkaException e) {
    producer.abortTransaction();  // 롤백
}
```

---

## Key 설계 전략

| 요구사항 | Key 선택 | 이유 |
|----------|---------|------|
| 사용자별 순서 보장 | userId | 같은 파티션 → 순서 보장 |
| 주문별 순서 보장 | orderId | 주문 이벤트 순서 유지 |
| 균등 분산 (순서 불필요) | UUID/random | 파티션 균등 분배 |
| 디바이스별 최신 상태 | deviceId | compacted topic에서 최신 유지 |

### 핫 파티션 방지
```java
// Bad: 소수의 key에 트래픽 집중
// key = "VIP" → 하나의 파티션에 몰림

// Good: key에 salt 추가 (순서 불필요 시)
String key = userId + "-" + (System.currentTimeMillis() % 10);

// Good: Custom Partitioner (특정 로직)
public class CustomPartitioner implements Partitioner {
    public int partition(String topic, Object key, ...) {
        // 비즈니스 로직 기반 파티션 결정
    }
}
```

---

## 대용량 메시지 처리

### 방법 1: 압축
```properties
compression.type=zstd       # 높은 압축률
max.request.size=10485760   # 10MB (기본 1MB)
```

### 방법 2: Claim Check 패턴
```
Producer → S3에 대용량 데이터 저장 → Kafka에 S3 URL만 전송
Consumer → Kafka에서 URL 수신 → S3에서 데이터 다운로드
```

### 방법 3: Chunking
- 대용량 메시지를 여러 청크로 분할
- 헤더에 chunk-id, total-chunks, sequence 포함
- Consumer에서 재조립
