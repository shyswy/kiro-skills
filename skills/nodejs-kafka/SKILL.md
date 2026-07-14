---
name: nodejs-kafka
description: |
  kafkajs 기반 Node.js/TypeScript Kafka Consumer/Producer 구현 패턴 가이드.
  Graceful shutdown, Rebalance 핸들링, Batch processing, Retry + DLQ,
  Event Envelope, Correlation ID 전파, Schema validation을 다룬다.
  kafka-msk 스킬이 인프라/설정 레벨이라면, 이 스킬은 Node.js 코드 구현에 집중한다.
  트리거: kafkajs, Node.js Kafka, TypeScript Kafka, Node consumer, Node producer,
  카프카 노드, 노드 카프카, kafkajs consumer, kafkajs producer,
  Kafka graceful shutdown Node, Kafka batch processing Node,
  event-driven Node.js, correlation ID, event envelope
license: MIT
---

# Node.js + Kafka (kafkajs) Patterns

## kafkajs 기본 셋업

```typescript
import { Kafka, logLevel } from 'kafkajs';

const kafka = new Kafka({
  clientId: process.env.SERVICE_NAME || 'my-service',
  brokers: (process.env.KAFKA_BROKERS || 'localhost:9092').split(','),
  logLevel: logLevel.WARN,
  // AWS MSK IAM 인증 시
  ssl: true,
  sasl: {
    mechanism: 'oauthbearer',
    oauthBearerProvider: async () => {
      const { generateAuthToken } = await import('aws-msk-iam-sasl-signer-js');
      const token = await generateAuthToken({ region: process.env.AWS_REGION || 'ap-northeast-2' });
      return { value: token.token };
    },
  },
});
```

---

## Consumer 패턴

### Graceful Shutdown

kafkajs consumer는 `disconnect()` 호출 시 in-flight 메시지 처리를 기다린 후 종료.

```typescript
const consumer = kafka.consumer({ groupId: 'my-group' });

async function startConsumer(): Promise<void> {
  await consumer.connect();
  await consumer.subscribe({ topics: ['my-topic'], fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ message }) => {
      await processMessage(message);
    },
  });
}

// Graceful shutdown
const signals: NodeJS.Signals[] = ['SIGTERM', 'SIGINT'];
for (const signal of signals) {
  process.on(signal, async () => {
    console.log(`${signal} received, disconnecting consumer...`);
    await consumer.disconnect(); // in-flight 처리 완료 대기
    process.exit(0);
  });
}
```

### Batch Processing (eachBatch)

고처리량 시나리오에서는 `eachBatch`가 `eachMessage`보다 효율적.

```typescript
await consumer.run({
  eachBatch: async ({ batch, heartbeat, resolveOffset, commitOffsetsIfNecessary }) => {
    for (const message of batch.messages) {
      try {
        await processMessage(message);
        resolveOffset(message.offset); // 이 메시지까지 처리 완료 표시
      } catch (error) {
        // 실패 메시지 — DLQ로 라우팅 후 계속 진행
        await sendToDLQ(batch.topic, message, error as Error);
        resolveOffset(message.offset);
      }
      await heartbeat(); // 긴 처리 중 session timeout 방지
    }
    await commitOffsetsIfNecessary();
  },
});
```

**`eachMessage` vs `eachBatch` 선택 기준:**

| 기준 | eachMessage | eachBatch |
|------|-------------|-----------|
| 단순성 | ✅ 간단 | 복잡 (offset 수동 관리) |
| 성능 | 메시지당 커밋 → 느림 | 배치 커밋 → 빠름 |
| 에러 핸들링 | 하나 실패 → 전체 재시도 | 개별 skip/DLQ 가능 |
| heartbeat | 자동 | 수동 호출 필요 |
| 적합 | 저부하, 단순 로직 | 고부하, 부분 실패 허용 |

### Retry + DLQ 패턴

```typescript
const MAX_RETRIES = 3;

async function processWithRetry(message: KafkaMessage, topic: string): Promise<void> {
  const retryCount = parseInt(message.headers?.['retry-count']?.toString() || '0');

  try {
    await processMessage(message);
  } catch (error) {
    if (retryCount < MAX_RETRIES) {
      // Retry topic으로 재발행 (exponential backoff는 consumer 측 delay로 구현)
      await producer.send({
        topic: `${topic}.retry`,
        messages: [{
          ...message,
          headers: { ...message.headers, 'retry-count': String(retryCount + 1) },
        }],
      });
    } else {
      // DLQ로 라우팅
      await sendToDLQ(topic, message, error as Error);
    }
  }
}

async function sendToDLQ(topic: string, message: KafkaMessage, error: Error): Promise<void> {
  await producer.send({
    topic: `${topic}.DLQ`,
    messages: [{
      key: message.key,
      value: message.value,
      headers: {
        ...message.headers,
        'dlq-reason': error.message,
        'dlq-timestamp': new Date().toISOString(),
        'original-topic': topic,
      },
    }],
  });
}
```

### Consumer Group 전략

```typescript
// 고부하 토픽: 전용 consumer group (독립 스케일링)
consumer.subscribe({ topics: ['device.status'], fromBeginning: false });

// 저부하 토픽: 하나의 consumer group으로 묶기
consumer.subscribe({ topics: ['incident.created', 'group.changed'], fromBeginning: false });
```

**Static Membership** (rebalance 최소화):
```typescript
const consumer = kafka.consumer({
  groupId: 'my-group',
  sessionTimeout: 30_000,
  // Static membership — Pod 재시작 시 rebalance 방지
  groupInstanceId: `${process.env.HOSTNAME || 'local'}-${process.env.POD_NAME || '0'}`,
});
```

---

## Producer 패턴

### Idempotent Producer

```typescript
const producer = kafka.producer({
  idempotent: true,           // 중복 전송 방지
  maxInFlightRequests: 5,     // idempotent 시 최대 5
  transactionalId: undefined, // transaction 미사용 시 undefined
});

await producer.connect();

await producer.send({
  topic: 'order.created',
  messages: [{
    key: orderId,             // 같은 key → 같은 partition → 순서 보장
    value: JSON.stringify(event),
    headers: {
      'event-type': 'OrderCreated',
      'event-id': eventId,
      'correlation-id': correlationId,
    },
  }],
});
```

### Compression

```typescript
import { CompressionTypes } from 'kafkajs';

await producer.send({
  topic: 'high-volume-topic',
  compression: CompressionTypes.LZ4, // 속도 우선. ZSTD는 압축률 우선.
  messages: [...],
});
```

---

## Event-Driven MSA 실전 패턴

### Event Envelope

```typescript
interface EventEnvelope<T> {
  event_id: string;          // UUID v4 (멱등성 키)
  event_type: string;        // domain.entity.action (예: order.payment.completed)
  timestamp: string;         // ISO 8601
  schema_version: number;    // 스키마 버전
  correlation_id: string;    // 요청 추적 (HTTP → Kafka → downstream)
  causation_id: string;      // 원인 이벤트 ID
  source: string;            // 발행 서비스명
  payload: T;
}

function createEnvelope<T>(type: string, payload: T, correlationId: string, causationId?: string): EventEnvelope<T> {
  return {
    event_id: crypto.randomUUID(),
    event_type: type,
    timestamp: new Date().toISOString(),
    schema_version: 1,
    correlation_id: correlationId,
    causation_id: causationId || correlationId,
    source: process.env.SERVICE_NAME || 'unknown',
    payload,
  };
}
```

### Correlation ID 전파

```
HTTP Request (x-correlation-id: abc-123)
    → Kafka Producer (header: correlation-id: abc-123)
        → Consumer (읽어서 context에 보관)
            → 하위 이벤트 발행 (header: correlation-id: abc-123)
            → 로그 (correlationId: abc-123)
```

```typescript
// Express 미들웨어
app.use((req, res, next) => {
  req.correlationId = req.headers['x-correlation-id'] as string || crypto.randomUUID();
  next();
});

// Kafka 헤더에서 추출
function extractCorrelationId(message: KafkaMessage): string {
  return message.headers?.['correlation-id']?.toString() || crypto.randomUUID();
}
```

---

## 운영 패턴

### Health Check

```typescript
let isConsumerReady = false;

consumer.on('consumer.connect', () => { isConsumerReady = true; });
consumer.on('consumer.disconnect', () => { isConsumerReady = false; });
consumer.on('consumer.crash', () => { isConsumerReady = false; });

// HTTP health endpoint
app.get('/health', (req, res) => {
  res.status(isConsumerReady ? 200 : 503).json({ kafka: isConsumerReady });
});
```

### Structured Logging

```typescript
import { Logger } from '@bc/shared-common'; // 또는 pino

const logger = new Logger('KafkaConsumer');

// 메시지 처리 시작/완료 로깅
logger.info('[KAFKA_IN]', {
  topic, partition, offset: message.offset,
  correlationId: extractCorrelationId(message),
  key: message.key?.toString(),
});
```

---

## 관련 스킬 참조
- `kafka-msk` — Kafka 인프라 설계, 파티션 전략, MSK 운영 (Java/설정 레벨)
- `architecture` → references/event-driven-patterns.md — Outbox, Saga, CQRS (설계 레벨)
- `nodejs-typescript` — graceful-shutdown, error-handling (Node.js 범용 패턴)
- `contract-testing` — Producer fixture + Consumer schema 계약 테스트
- `testcontainers-node` — Kafka Testcontainers 통합 테스트
