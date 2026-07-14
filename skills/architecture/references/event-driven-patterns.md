# Event-Driven Architecture Patterns

> Based on: [travisjneuman/.claude/event-driven-architecture](https://github.com/travisjneuman/.claude) (MIT License)
> Tier 2: base + 커스텀 확장 (CQRS, Event Sourcing, Choreography vs Orchestration 추가)

---

## Core Principles

1. **Events are facts, commands are requests** — Events describe something that happened (`OrderPlaced`). Commands request an action (`ProcessPayment`). Events are broadcast, commands are point-to-point.
2. **Idempotency is not optional** — At-least-once delivery means duplicates happen. Every consumer must handle them (event ID dedup, DB constraints, version checks).
3. **Schema evolution without breaking consumers** — Add fields, never remove or rename. Version schemas explicitly.
4. **Dead letters are not garbage** — DLQ = bugs, data issues, edge cases. Monitor, alert, and build replay tooling.
5. **Local transactions, eventual consistency** — Each service owns its data. Cross-service consistency is eventual.

---

## Pattern 1: Transactional Outbox

**문제:** DB 커밋 + 이벤트 발행의 원자성 보장 불가 (dual write problem).

**해결:** 같은 DB 트랜잭션에 outbox 테이블 INSERT → 별도 프로세스가 polling/CDC로 발행.

```typescript
interface OutboxEvent {
  id: string;
  aggregateType: string;
  aggregateId: string;
  eventType: string;
  payload: Record<string, unknown>;
  createdAt: Date;
  publishedAt: Date | null;
}

// Step 1: Business operation + outbox write in one transaction
async function placeOrder(order: CreateOrderInput): Promise<Order> {
  return await db.transaction(async (tx) => {
    const created = await tx.orders.insert({ ...order, status: 'PLACED' });

    await tx.outboxEvents.insert({
      id: crypto.randomUUID(),
      aggregateType: 'Order',
      aggregateId: created.id,
      eventType: 'OrderPlaced',
      payload: { orderId: created.id, total: created.total },
    });

    return created;
  });
}

// Step 2: Poller publishes to Kafka
async function processOutbox(): Promise<void> {
  const unpublished = await db.outboxEvents.findMany({
    where: { publishedAt: null },
    orderBy: { createdAt: 'asc' },
    take: 100,
  });

  for (const event of unpublished) {
    await kafka.producer.send({
      topic: `${event.aggregateType}.${event.eventType}`,
      messages: [{ key: event.aggregateId, value: JSON.stringify(event) }],
    });
    await db.outboxEvents.update(event.id, { publishedAt: new Date() });
  }
}
```

**구현 방식 비교:**

| 방식 | 장점 | 단점 |
|------|------|------|
| Polling Publisher | 단순 구현, DB만 필요 | 지연 (poll 주기), DB 부하 |
| CDC (Debezium) | 실시간, DB 부하 없음 | 인프라 복잡, Debezium 운영 비용 |

---

## Pattern 2: Idempotent Event Consumer

**원칙:** 모든 consumer는 동일 메시지를 N번 처리해도 결과가 동일해야 함.

```typescript
async function handleEvent(event: DomainEvent): Promise<void> {
  // Idempotency check
  const processed = await db.processedEvents.findByEventId(event.eventId);
  if (processed) return; // 이미 처리됨 — skip

  await db.transaction(async (tx) => {
    // 처리 기록 + 비즈니스 로직을 같은 트랜잭션에
    await tx.processedEvents.insert({ eventId: event.eventId, processedAt: new Date() });
    await businessLogic(event, tx);
  });
}
```

**Idempotency Key 전략:**

| 방식 | 구현 | 적합 |
|------|------|------|
| Event ID (DB unique) | `processed_events` 테이블 + unique constraint | 정확한 중복 방지 |
| Redis SET NX | `SET event:{id} 1 NX EX 86400` | 빠른 체크, TTL 기반 |
| Aggregate version | `UPDATE ... WHERE version = expected` | Optimistic locking |

---

## Pattern 3: Saga

### Choreography vs Orchestration

| 비교 축 | Choreography | Orchestration |
|---------|-------------|---------------|
| 제어 방식 | 각 서비스가 이벤트 발행/구독 | 중앙 Orchestrator가 커맨드 발행 |
| 결합도 | 매우 느슨 | Orchestrator에 집중 |
| 가시성 | 낮음 (이벤트 흐름 추적 어려움) | 높음 (중앙에서 상태 관리) |
| 복잡도 | 서비스 수 증가 시 급증 | 선형 증가 |
| 보상 트랜잭션 | 각 서비스가 독립 구현 | Orchestrator가 순서 제어 |
| 적합 | 3개 이하 서비스, 단순 플로우 | 4개+ 서비스, 복잡한 보상 로직 |

### Orchestration 구현

```typescript
interface SagaStep {
  name: string;
  execute: (ctx: SagaContext) => Promise<void>;
  compensate: (ctx: SagaContext) => Promise<void>;
}

async function executeSaga(steps: SagaStep[], context: SagaContext): Promise<void> {
  const completed: SagaStep[] = [];

  for (const step of steps) {
    try {
      await step.execute(context);
      completed.push(step);
    } catch (error) {
      // Compensate in reverse order
      for (const done of completed.reverse()) {
        try {
          await done.compensate(context);
        } catch (compensateError) {
          // CRITICAL: 보상 실패 → 수동 개입 필요. 알림 발송.
          await alertOps({ type: 'saga_compensation_failure', step: done.name, error: compensateError });
        }
      }
      throw new SagaFailedError(step.name, error as Error);
    }
  }
}
```

### Choreography 흐름

```
OrderService          PaymentService        InventoryService
    │                      │                      │
    ├─ OrderPlaced ──────►│                      │
    │                      ├─ PaymentCompleted ──►│
    │                      │                      ├─ InventoryReserved ──► (완료)
    │                      │                      │
    │                      │  (실패 시)            │
    │                      ├─ PaymentFailed ─────►│
    │  ◄─ OrderCancelled ──┤                      ├─ InventoryReleased
```

---

## Pattern 4: CQRS (Command Query Responsibility Segregation)

**핵심:** 쓰기 모델(Command) ≠ 읽기 모델(Query). 각각 최적화된 저장소/스키마 사용.

```
┌─────────────┐         ┌─────────────┐
│  Command    │         │   Query     │
│  (Write)    │         │   (Read)    │
│  ─────────  │         │  ─────────  │
│  Normalized │  Event  │  Denormalized│
│  PostgreSQL │────────►│  OpenSearch  │
│  (정합성)   │ 동기화   │  (검색최적화) │
└─────────────┘         └─────────────┘
```

**동기화 방식:** 이벤트 기반 Projection
- Command 측에서 이벤트 발행 (OrderPlaced)
- Projector가 이벤트를 소비하여 Read Model 업데이트
- Eventually Consistent (수 초~수 분 지연 허용)

**적합 케이스:**
- 읽기/쓰기 부하 비대칭 (읽기 10:1 이상)
- 복잡한 조회 요구사항 (전문 검색, 다차원 필터링)
- 읽기 성능이 핵심 NFR

**부적합 케이스:**
- 단순 CRUD (오버엔지니어링)
- 쓰기 직후 즉시 읽기 필요 (강한 일관성 필수)

---

## Pattern 5: Event Sourcing

**핵심:** 현재 상태 = Σ(모든 이벤트). 상태 변경을 이벤트로 저장하고, 리플레이로 복원.

```typescript
// Event Store (append-only)
interface StoredEvent {
  eventId: string;
  aggregateId: string;
  aggregateType: string;
  eventType: string;
  version: number;        // 시퀀스 (낙관적 동시성 제어)
  payload: unknown;
  timestamp: Date;
}

// Aggregate 복원
function rehydrate(events: StoredEvent[]): OrderAggregate {
  let state: OrderAggregate = createEmpty();
  for (const event of events) {
    state = applyEvent(state, event);
  }
  return state;
}

// Snapshot (성능 최적화)
// 매 N번째 이벤트마다 현재 상태 스냅샷 저장
// 복원 = snapshot + 이후 이벤트만 리플레이
```

**CQRS와의 시너지:** Event Sourcing의 이벤트 스트림 → Projector → Read Model 업데이트

**주의사항:**
- 이벤트 스키마 변경 시 기존 이벤트 마이그레이션 필요 (upcasting)
- 이벤트 수 증가 시 리플레이 느려짐 → Snapshot 필수
- 삭제(GDPR) 처리가 복잡 (crypto-shredding 패턴)

---

## Pattern 6: Event Schema Evolution

**호환성 레벨:**

| 레벨 | 규칙 | Consumer 영향 |
|------|------|--------------|
| Backward | 새 스키마로 구 데이터 읽기 가능 | 신규 Consumer가 구 이벤트 처리 가능 |
| Forward | 구 스키마로 새 데이터 읽기 가능 | 기존 Consumer가 신규 이벤트 처리 가능 |
| Full | 양방향 호환 | 가장 안전, 가장 제한적 |

**안전한 변경:**
- 필드 추가 (default 값 필수)
- Optional 필드 삭제 (Forward 호환 시)

**위험한 변경 (Breaking):**
- 필드 이름 변경
- 타입 변경 (string → number)
- Required 필드 추가 (기존 이벤트에 없으므로)

**Upcasting 패턴:**

```typescript
function upcastEvent(event: StoredEvent): CurrentVersionEvent {
  switch (event.version) {
    case 1: return upcastV1toV2(event.payload);
    case 2: return upcastV2toV3(event.payload);
    case 3: return event.payload as CurrentVersionEvent;
    default: throw new Error(`Unknown event version: ${event.version}`);
  }
}
```

---

## Pattern 7: Dead Letter Queue Handling

**DLQ 라우팅 기준:**
- 재시도 횟수 초과 (maxReceiveCount/maxRetries)
- 스키마 불일치 (파싱 불가)
- 비즈니스 규칙 위반 (처리 불가능한 상태)

**재처리 워크플로우:**
```
Main Topic → Consumer (실패 3회) → DLQ Topic
                                       │
                                       ▼
                              알림 (CloudWatch → Slack)
                                       │
                                       ▼
                              수동 검토 → 수정 → Replay to Main Topic
```

**Replay 도구:** DLQ에서 메시지를 읽어 수정/필터 후 원본 topic에 재발행

---

## Message Broker Selection Guide

| Broker | Best For | Ordering | Throughput | Persistence |
|--------|----------|----------|-----------|-------------|
| Kafka | High-throughput streaming, log compaction | Per-partition | millions/sec | Configurable retention |
| RabbitMQ | Task queues, routing, request-reply | Per-queue | 100k/sec | Optional |
| SQS/SNS | Serverless, AWS-native, low ops | Per-FIFO queue | 3k/sec FIFO | 14-day retention |
| NATS | Low-latency, cloud-native | JetStream | Very high | JetStream |

---

## Anti-Patterns

| Anti-Pattern | 왜 나쁜가 | 올바른 접근 |
|---|---|---|
| Dual writes (DB + event) 원자성 없이 | 한쪽 실패 시 데이터 불일치 | Transactional Outbox |
| Consumer에 멱등 처리 없음 | 재전송 시 중복 처리 | Event ID dedup |
| Event payload > 1MB | 브로커 제한, 느린 처리 | Claim check (참조만 전송) |
| 동기식 이벤트 처리 | 비동기 아키텍처 목적 무효화 | 큐 기반 비동기 처리 |
| DLQ 미설정 | 실패 메시지 유실 또는 블록 | DLQ + 알림 + replay |
| 스키마 변경 시 호환성 무시 | Consumer 깨짐 | Backward-compatible evolution |
| 여러 곳에서 이벤트 발행 | 이벤트 형태 불일치 | Single publish point |

---

## Checklist

- [ ] Transactional Outbox for atomic DB + event writes
- [ ] Every consumer is idempotent (event ID dedup)
- [ ] DLQ configured with alerting and replay tooling
- [ ] Event schemas versioned with backward-compatible evolution
- [ ] Consumer groups configured per service
- [ ] Retry with exponential backoff before DLQ
- [ ] Saga or choreography for cross-service workflows
- [ ] Monitoring: consumer lag, DLQ depth, processing errors
- [ ] Event ordering preserved where needed (partition keys)
- [ ] Broker cluster is fault-tolerant (replication)

---

## Attribution

- Based on: [travisjneuman/.claude/event-driven-architecture](https://github.com/travisjneuman/.claude) (MIT License)
- Tier: 2 (base + 커스텀 확장)
- 확장 내용: CQRS 상세, Event Sourcing 상세, Choreography vs Orchestration 비교, 한국어 Anti-Patterns, Schema Evolution 상세
