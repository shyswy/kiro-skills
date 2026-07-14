---
name: contract-testing
description: |
  Event-Driven MSA에서 Producer-Consumer 간 이벤트 계약을 정의하고 테스트하는 패턴 가이드.
  Producer fixture와 Consumer schema를 교차 검증하여 서비스 간 계약 깨짐을 CI에서 조기 감지한다.
  이 스킬은 계약 테스트, contract test, producer consumer 계약, 이벤트 스키마 검증,
  fixture 동기화, 서비스 간 통신 계약, 이벤트 호환성, schema breaking change 등을 다룬다.
  Kafka, SQS, EventBridge 등 메시징 시스템 무관하게 적용 가능한 범용 원칙 + TypeScript 구현 예시.
  트리거: contract test, 계약 테스트, producer fixture, consumer schema, 이벤트 계약,
  schema 깨짐, breaking change 감지, 서비스 간 계약, event contract, CDC test
license: MIT
---

# Contract Testing — Producer-Consumer 이벤트 계약 검증

## 왜 필요한가

Event-Driven MSA에서 Producer와 Consumer는 독립 배포된다.
Producer가 이벤트 구조를 변경하면 Consumer가 깨지는데, 이를 **배포 전**에 감지하는 게 계약 테스트의 목적.

문제 시나리오:
1. Producer가 `device_id` → `deviceId`로 필드명 변경 (camelCase 통일)
2. Consumer의 Joi schema는 여전히 `device_id`를 required로 기대
3. 배포 후 런타임에서야 validation 실패 → 메시지 유실

계약 테스트가 있으면 CI 단계에서 이걸 잡는다.

---

## 핵심 개념

### Producer Fixture
Producer가 **실제로 발행하는 페이로드**와 동일한 구조의 JSON 객체.
Producer 코드의 publish 함수가 만드는 것과 1:1 대응해야 한다.

### Consumer Schema
Consumer가 메시지를 수신할 때 적용하는 **검증 규칙** (Joi, Zod, JSON Schema 등).
이걸 통과해야 비즈니스 로직으로 진입한다.

### 계약 테스트
Producer fixture를 Consumer schema에 통과시켜서 호환성을 검증하는 테스트.

---

## 디렉토리 구조 패턴

```
src/
├── module-a/           # Producer
│   └── services/
│       └── publish-event.ts
├── module-b/           # Consumer
│   └── validators/
│       └── event.validator.ts
└── shared/
    └── contracts/
        ├── producers/
        │   └── module-a.producers.ts   ← Producer fixture
        └── tests/
            └── module-b-consumer.contract.spec.ts  ← 계약 테스트
```

**핵심 원칙:**
- Fixture는 `shared/contracts/producers/`에 모은다
- 테스트는 `shared/contracts/tests/`에 모은다
- Producer와 Consumer 양쪽이 같은 레포에 있으면 단일 디렉토리. 다른 레포면 npm 패키지로 fixture 공유

---

## 구현 패턴

### Step 1: Producer Fixture 정의

```typescript
// shared/contracts/producers/order.producers.ts

/**
 * order.created event fixture
 * Producer: order-service (order.service.ts)
 * Consumer: notification-service, billing-service
 *
 * ⚠️ order-service의 publish 코드가 변경되면 이 fixture도 반드시 업데이트.
 */
export const ORDER_CREATED_FIXTURE = {
  event_id: 'evt-contract-001',
  event_type: 'OrderCreated' as const,
  order_id: 'ord-001',
  customer_id: 'cust-001',
  total_amount: 15000,
  currency: 'KRW',
  occurred_at: '2026-06-01T10:00:00.000Z',
  items: [
    { product_id: 'prod-001', quantity: 2, unit_price: 7500 },
  ],
};

/**
 * Minimal fixture — optional 필드가 전부 null/빈 값인 경우
 */
export const ORDER_CREATED_MINIMAL_FIXTURE = {
  event_id: 'evt-contract-002',
  event_type: 'OrderCreated' as const,
  order_id: 'ord-002',
  customer_id: 'cust-002',
  total_amount: 0,
  currency: 'KRW',
  occurred_at: '2026-06-01T10:01:00.000Z',
  items: [],
};
```

**Fixture 작성 원칙:**
- 실제 코드의 publish 함수 출력과 **구조적으로 동일**해야 함
- Standard fixture (모든 필드 채움) + Minimal fixture (optional 필드 null) 최소 2개
- `as const` 타입 단언으로 리터럴 타입 유지
- 주석에 Producer 위치와 Consumer 목록 명시

### Step 2: Consumer Schema 정의

```typescript
// notification-service/validators/order-event.validator.ts
import Joi from 'joi';

export const orderCreatedSchema = Joi.object({
  event_id: Joi.string().required(),
  event_type: Joi.string().valid('OrderCreated').required(),
  order_id: Joi.string().required(),
  customer_id: Joi.string().required(),
  total_amount: Joi.number().required(),
  currency: Joi.string().required(),
  occurred_at: Joi.string().isoDate().required(),
  items: Joi.array().items(
    Joi.object({
      product_id: Joi.string().required(),
      quantity: Joi.number().integer().min(1).required(),
      unit_price: Joi.number().required(),
    })
  ).required(),
}).options({ abortEarly: false, stripUnknown: true });
```

**`stripUnknown: true`가 중요한 이유:**
- Producer가 새 필드를 추가해도 Consumer가 깨지지 않음 (forward compatibility)
- Consumer는 자신이 아는 필드만 사용

### Step 3: 계약 테스트

```typescript
// shared/contracts/tests/notification-consumer.contract.spec.ts
import { orderCreatedSchema } from '../../../notification/validators/order-event.validator';
import {
  ORDER_CREATED_FIXTURE,
  ORDER_CREATED_MINIMAL_FIXTURE,
} from '../producers/order.producers';

describe('Contract: notification consumer ← order producer', () => {
  it('should accept standard OrderCreated event', () => {
    const { error } = orderCreatedSchema.validate(ORDER_CREATED_FIXTURE);
    expect(error).toBeUndefined();
  });

  it('should accept minimal OrderCreated event', () => {
    const { error } = orderCreatedSchema.validate(ORDER_CREATED_MINIMAL_FIXTURE);
    expect(error).toBeUndefined();
  });

  it('should preserve required fields after strip', () => {
    const { value } = orderCreatedSchema.validate(ORDER_CREATED_FIXTURE);
    expect(value.event_id).toBe(ORDER_CREATED_FIXTURE.event_id);
    expect(value.order_id).toBe(ORDER_CREATED_FIXTURE.order_id);
  });
});
```

---

## 계약 깨짐 시나리오와 대응

| 변경 유형 | 계약 테스트 결과 | 대응 |
|-----------|----------------|------|
| Producer가 optional 필드 추가 | ✅ 통과 (stripUnknown) | 안전. Consumer가 필요하면 schema 확장 |
| Producer가 required 필드 삭제 | ❌ 실패 | Consumer schema에서 해당 필드를 optional로 변경 |
| Producer가 필드명 변경 | ❌ 실패 | 양측 협의 후 동시 업데이트 or 과도기 양쪽 지원 |
| Consumer가 새 필드를 required로 추가 | ❌ 실패 (기존 fixture에 없음) | fixture 업데이트 + Producer에 필드 추가 요청 |
| 타입 변경 (string → number) | ❌ 실패 | Breaking change. 버전 분리 필요 |

---

## CI 연동

```yaml
# .gitlab-ci.yml (또는 GitHub Actions)
contract-test:
  stage: test
  script:
    - npm run test:contract
  rules:
    - changes:
        - src/shared/contracts/**/*
        - src/**/validators/**/*
```

**CI에서 contract test를 gate로 사용**: 계약 테스트 실패 시 MR 머지 차단.

---

## 다중 레포 환경에서의 계약 관리

모노레포가 아닌 경우:
1. **Fixture 패키지**: Producer가 fixture를 npm 패키지로 발행 (`@company/order-events-fixture`)
2. **Consumer가 의존**: devDependencies에 fixture 패키지 추가
3. **버전 관리**: fixture 패키지 버전 = 이벤트 스키마 버전

또는:
- **공유 Git submodule**: `contracts/` 디렉토리를 별도 레포로 관리
- **Schema Registry 연동**: Confluent/Glue Schema Registry에서 Avro/Protobuf로 관리

---

## Anti-patterns

1. **Fixture가 실제 코드와 동기화 안 됨** — Producer 코드 변경 시 fixture 업데이트를 강제하는 방법 필요 (lint rule, code review checklist)
2. **Consumer schema가 너무 loose** — `Joi.any()`로 전부 받으면 계약 테스트 의미 없음
3. **fixture를 테스트에서만 인라인 정의** — 재사용 불가, 다중 consumer 간 일관성 없음
4. **required 필드를 Consumer가 임의로 추가** — Producer와 협의 없이 required 추가하면 계약 깨짐의 원인

---

## Zod 버전 예시

```typescript
import { z } from 'zod';

export const orderCreatedSchema = z.object({
  event_id: z.string(),
  event_type: z.literal('OrderCreated'),
  order_id: z.string(),
  customer_id: z.string(),
  total_amount: z.number(),
  currency: z.string(),
  occurred_at: z.string().datetime(),
  items: z.array(z.object({
    product_id: z.string(),
    quantity: z.number().int().min(1),
    unit_price: z.number(),
  })),
}).passthrough(); // stripUnknown 대신 passthrough로 추가 필드 허용

// 계약 테스트
const result = orderCreatedSchema.safeParse(ORDER_CREATED_FIXTURE);
expect(result.success).toBe(true);
```
