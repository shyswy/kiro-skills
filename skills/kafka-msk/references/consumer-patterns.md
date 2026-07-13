# Consumer 패턴 상세

## Rebalance 전략

### Rebalance 발생 조건
- Consumer 추가/제거
- Consumer heartbeat 실패 (session.timeout.ms 초과)
- Consumer poll 간격 초과 (max.poll.interval.ms)
- Topic 파티션 수 변경
- 구독 패턴 변경

### Assignor 비교
| Assignor | 특징 | 용도 |
|----------|------|------|
| RangeAssignor | 연속 파티션 할당 | 기본값, 단순 |
| RoundRobinAssignor | 균등 분배 | 여러 토픽 구독 시 |
| StickyAssignor | 기존 할당 유지 최대화 | rebalance 영향 최소화 |
| CooperativeStickyAssignor | 점진적 재할당 (stop-the-world 없음) | **권장** |

### Cooperative Rebalancing 설정
```properties
partition.assignment.strategy=org.apache.kafka.clients.consumer.CooperativeStickyAssignor
```
장점: 전체 consumer가 멈추지 않고, 이동 필요한 파티션만 재할당

### Static Membership (Rebalance 최소화)
```properties
group.instance.id=consumer-host-1  # 인스턴스별 고유 ID
session.timeout.ms=300000          # 5분 (재시작 시간 고려)
```
- Consumer 재시작 시 같은 파티션 재할당 (rebalance 없음)
- session.timeout 내 복귀하면 파티션 유지

---

## Consumer Lag 대응

### Lag 모니터링
```bash
# kafka-consumer-groups CLI
kafka-consumer-groups.sh --bootstrap-server broker:9092 \
  --group my-group --describe

# 출력: TOPIC, PARTITION, CURRENT-OFFSET, LOG-END-OFFSET, LAG
```

### Lag 대응 전략
| Lag 수준 | 대응 |
|----------|------|
| 일시적 스파이크 | 대기 (자동 회복) |
| 지속적 증가 | Consumer 인스턴스 추가 (파티션 수 이내) |
| Consumer 수 = 파티션 수인데도 lag | max.poll.records 증가, 처리 로직 최적화 |
| 복구 불가 수준 | Consumer 리셋 (latest) + 누락 데이터 별도 처리 |

### Consumer 처리량 최적화
```properties
max.poll.records=500         # 한 번에 가져올 메시지 수 (기본 500)
fetch.min.bytes=1048576      # 최소 1MB 모일 때까지 대기
fetch.max.wait.ms=500        # 최대 대기 시간
max.partition.fetch.bytes=1048576  # 파티션당 최대 fetch 크기
```

---

## 멱등 처리 (Idempotent Consumer)

### 방법 1: Deduplication Table
```sql
CREATE TABLE processed_events (
    event_id VARCHAR(64) PRIMARY KEY,
    processed_at TIMESTAMP DEFAULT NOW()
);

-- Consumer 로직
BEGIN;
INSERT INTO processed_events (event_id) VALUES ('evt-123')
ON CONFLICT (event_id) DO NOTHING;  -- 이미 처리됨 → skip
-- 비즈니스 로직 실행 (INSERT 성공 시에만)
COMMIT;
```

### 방법 2: Upsert (자연스러운 멱등)
```sql
-- 같은 메시지 재처리해도 결과 동일
INSERT INTO device_status (device_id, status, updated_at)
VALUES ('dev-1', 'online', NOW())
ON CONFLICT (device_id) DO UPDATE SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at;
```

### 방법 3: Conditional Update
```sql
-- version/timestamp 기반 (오래된 이벤트 무시)
UPDATE orders SET status = 'shipped', version = 5
WHERE id = 123 AND version < 5;
```

---

## Offset 관리

### 수동 커밋 패턴
```java
while (true) {
    ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
    for (ConsumerRecord<String, String> record : records) {
        process(record);  // 처리 완료 후
    }
    consumer.commitSync();  // 동기 커밋 (안전)
    // 또는 consumer.commitAsync();  // 비동기 (빠르지만 실패 시 중복 가능)
}
```

### Per-Partition 커밋 (세밀한 제어)
```java
for (TopicPartition partition : records.partitions()) {
    List<ConsumerRecord<String, String>> partitionRecords = records.records(partition);
    for (ConsumerRecord<String, String> record : partitionRecords) {
        process(record);
    }
    long lastOffset = partitionRecords.get(partitionRecords.size() - 1).offset();
    consumer.commitSync(Map.of(partition, new OffsetAndMetadata(lastOffset + 1)));
}
```

### Offset Reset 전략
```properties
auto.offset.reset=earliest  # 처음부터 (데이터 유실 방지)
auto.offset.reset=latest    # 최신부터 (과거 데이터 무시)
```

---

## Graceful Shutdown

```java
Runtime.getRuntime().addShutdownHook(new Thread(() -> {
    consumer.wakeup();  // poll()에서 WakeupException 발생
}));

try {
    while (running) {
        ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
        process(records);
        consumer.commitSync();
    }
} catch (WakeupException e) {
    // shutdown signal
} finally {
    consumer.commitSync();  // 마지막 offset 커밋
    consumer.close();       // consumer group 탈퇴 (즉시 rebalance)
}
```

---

## Error Handling 전략

### Retry + DLQ 패턴
```
Main Topic → Consumer → 처리 성공 → commit
                      → 처리 실패 (retriable) → Retry Topic (delay)
                      → 처리 실패 (non-retriable) → DLQ Topic
```

### Retry Topic with Backoff
```
order.events           → 첫 시도
order.events.retry-1   → 1분 후 재시도
order.events.retry-2   → 5분 후 재시도
order.events.retry-3   → 30분 후 재시도
order.events.DLQ       → 최종 실패
```

### Spring Kafka 예시
```java
@RetryableTopic(
    attempts = "4",
    backoff = @Backoff(delay = 60000, multiplier = 5),
    dltStrategy = DltStrategy.FAIL_ON_ERROR
)
@KafkaListener(topics = "order.events")
public void listen(OrderEvent event) {
    processOrder(event);  // 실패 시 자동 retry topic으로
}
```
