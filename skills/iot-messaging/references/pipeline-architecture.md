# IoT 메시지 파이프라인 아키텍처

## 전체 파이프라인 (MQTT → Kafka → ES/DB)

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│  Devices    │────▶│  IoT Core    │────▶│   Kafka     │────▶│  Consumers   │
│  (MQTT)     │     │  (Rule Engine)│     │   (MSK)     │     │              │
└─────────────┘     └──────────────┘     └─────────────┘     └──────┬───────┘
                                                                      │
                                              ┌───────────────────────┼───────────┐
                                              │                       │           │
                                         ┌────▼────┐           ┌─────▼───┐  ┌────▼────┐
                                         │   ES    │           │   RDS   │  │   S3    │
                                         │(검색/분석)│           │(상태 저장)│  │(아카이브)│
                                         └─────────┘           └─────────┘  └─────────┘
```

---

## IoT Core → Kafka 연동

### IoT Rule (SQL + Action)
```sql
-- IoT Core Rule SQL
SELECT
  topic(3) as deviceId,
  timestamp() as receivedAt,
  *
FROM 'devices/+/telemetry'
WHERE temperature > -40 AND temperature < 100  -- 기본 유효성 검증
```

### Rule Action: Kafka
```json
{
  "kafka": {
    "destinationArn": "arn:aws:kafka:ap-northeast-2:123456789:cluster/my-msk/...",
    "topic": "iot.raw.telemetry",
    "key": "${topic(3)}",
    "partition": "${topic(3)}"
  }
}
```

### 대안: IoT Core → Kinesis → Lambda → Kafka
```
IoT Core → Kinesis Data Streams → Lambda (정규화) → Kafka
```
장점: Kinesis가 버퍼 역할, Lambda에서 정규화 로직 실행

---

## Kafka Topic 설계 (IoT)

### Topic 구조
```
iot.raw.telemetry          # 원본 데이터 (정규화 전)
iot.normalized.telemetry   # 정규화된 이벤트
iot.device.status          # 디바이스 상태 (compacted)
iot.alerts                 # 임계값 초과 알림
iot.errors.normalization   # 정규화 실패 (DLQ)
```

### 설정
```
iot.raw.telemetry:
  partitions: 12 (디바이스 수 / 1000 기준)
  retention: 7d
  key: deviceId

iot.device.status:
  partitions: 6
  cleanup.policy: compact  # 최신 상태만 유지
  key: deviceId

iot.alerts:
  partitions: 3
  retention: 30d
```

---

## Consumer 파이프라인

### Consumer 1: Normalizer
```typescript
// iot.raw.telemetry → 정규화 → iot.normalized.telemetry
const consumer = kafka.consumer({ groupId: 'normalizer-group' });
await consumer.subscribe({ topic: 'iot.raw.telemetry' });

await consumer.run({
  eachMessage: async ({ message }) => {
    const raw = JSON.parse(message.value!.toString());
    const deviceType = detectDeviceType(raw);
    const normalized = registry.normalize(deviceType, raw);

    if (normalized) {
      await producer.send({
        topic: 'iot.normalized.telemetry',
        messages: [{ key: normalized.deviceId, value: JSON.stringify(normalized) }],
      });
    }
  },
});
```

### Consumer 2: State Updater
```typescript
// iot.normalized.telemetry → DynamoDB (최신 상태)
await consumer.run({
  eachMessage: async ({ message }) => {
    const event: NormalizedEvent = JSON.parse(message.value!.toString());

    // DynamoDB에 최신 상태 upsert
    await dynamodb.put({
      TableName: 'device-status',
      Item: {
        PK: `DEVICE#${event.deviceId}`,
        SK: 'CURRENT',
        ...event.metrics,
        lastUpdated: event.timestamp,
        deviceType: event.deviceType,
      },
    });

    // Compacted topic에도 발행 (다른 서비스 참조용)
    await producer.send({
      topic: 'iot.device.status',
      messages: [{ key: event.deviceId, value: JSON.stringify(event) }],
    });
  },
});
```

### Consumer 3: ES Indexer
```typescript
// iot.normalized.telemetry → OpenSearch (시계열 분석)
const batch: NormalizedEvent[] = [];

await consumer.run({
  eachBatch: async ({ batch: kafkaBatch }) => {
    const events = kafkaBatch.messages.map(m => JSON.parse(m.value!.toString()));

    // Bulk index
    const body = events.flatMap(event => [
      { index: { _index: `iot-telemetry-${event.timestamp.slice(0, 10)}` } },
      event,
    ]);

    await esClient.bulk({ body });
  },
});
```

### Consumer 4: Alert Engine
```typescript
// iot.normalized.telemetry → 임계값 체크 → iot.alerts
const thresholds: Record<string, { metric: string; operator: '>' | '<'; value: number }[]> = {
  'webos-tv': [
    { metric: 'temperature', operator: '>', value: 80 },
    { metric: 'cpu_usage', operator: '>', value: 95 },
  ],
  'sensor': [
    { metric: 'battery', operator: '<', value: 10 },
    { metric: 'temperature', operator: '>', value: 50 },
  ],
};

await consumer.run({
  eachMessage: async ({ message }) => {
    const event: NormalizedEvent = JSON.parse(message.value!.toString());
    const rules = thresholds[event.deviceType] || [];

    for (const rule of rules) {
      const metric = event.metrics[rule.metric];
      if (!metric) continue;

      const triggered = rule.operator === '>'
        ? (metric.value as number) > rule.value
        : (metric.value as number) < rule.value;

      if (triggered) {
        await producer.send({
          topic: 'iot.alerts',
          messages: [{
            key: event.deviceId,
            value: JSON.stringify({
              deviceId: event.deviceId,
              metric: rule.metric,
              value: metric.value,
              threshold: rule.value,
              operator: rule.operator,
              timestamp: event.timestamp,
            }),
          }],
        });
      }
    }
  },
});
```

---

## 스케일링 고려사항

| 구간 | 병목 | 대응 |
|------|------|------|
| IoT Core → Kafka | IoT Rule 처리량 | Rule 분리, Kinesis 버퍼 |
| Kafka 파티션 | 단일 파티션 처리량 | 파티션 수 증가 |
| Normalizer | CPU (파싱/변환) | Consumer 인스턴스 추가 |
| ES Indexer | ES 쓰기 처리량 | Bulk 크기 조정, shard 수 |
| DynamoDB | WCU 제한 | On-Demand 또는 Auto Scaling |

### 디바이스 규모별 권장
| 디바이스 수 | Kafka 파티션 | Consumer 인스턴스 | ES shard |
|------------|:-----------:|:----------------:|:--------:|
| ~1,000 | 6 | 2 | 2 |
| ~10,000 | 12 | 4 | 3 |
| ~100,000 | 24 | 8 | 5 |
| ~1,000,000 | 48+ | 16+ | 10+ |
