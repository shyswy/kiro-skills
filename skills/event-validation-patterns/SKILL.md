---
name: event-validation-patterns
description: |
  Kafka/SQS 등 메시징 consumer에서 이벤트 페이로드를 검증하고 도메인 모델로 변환하는 파이프라인 패턴.
  validate → transform → handle 구조, 실패 처리 전략, 스키마 버전 관리를 다룬다.
  Joi와 Zod 양쪽 예시를 포함하며, 선택 기준을 제시한다.
  트리거: 이벤트 검증, 메시지 validation, consumer schema, event transform,
  joi schema kafka, zod kafka, payload validation, event normalizer,
  이벤트 변환, 메시지 파싱, consumer 파이프라인
license: MIT
---

# Event Validation & Transform Patterns

## 핵심 구조: validate → transform → handle

메시징 consumer에서 이벤트를 받으면 3단계 파이프라인을 거친다:

```
Raw Kafka/SQS Message
        │
        ▼
   ┌─────────┐
   │ Validate │  ← Schema 검증 (구조, 타입, 필수값)
   └────┬────┘
        │ 실패 → skip + warn (또는 DLQ)
        ▼
   ┌───────────┐
   │ Transform │  ← Raw → Domain Model 변환
   └────┬──────┘
        │
        ▼
   ┌────────┐
   │ Handle │  ← 비즈니스 로직
   └────────┘
```

**왜 이렇게 분리하는가:**
- Validate: 잘못된 메시지를 비즈니스 로직 진입 전에 걸러냄. Producer 버그/스키마 불일치 조기 감지.
- Transform: Raw event 구조(snake_case, nested)를 도메인에 맞는 형태(camelCase, flat)로 정규화.
- Handle: 변환된 깨끗한 데이터로만 작업. 방어 코드 불필요.

---

## Joi 기반 패턴

### Schema 정의

```typescript
import Joi from 'joi';

export const deviceStatusSchema = Joi.object({
  device_id: Joi.string().required(),
  workspace_id: Joi.string().required(),
  timestamp: Joi.string().isoDate().required(),
  metrics: Joi.object({
    temperature: Joi.number().allow(null),
    fan_speed: Joi.number().allow(null),
    cpu_usage: Joi.number().min(0).max(100).allow(null),
  }).required(),
  firmware_version: Joi.string().optional(),
}).options({ abortEarly: false, stripUnknown: true });
```

**핵심 옵션:**
- `abortEarly: false`: 모든 에러를 한번에 수집 (디버깅 편의)
- `stripUnknown: true`: Producer가 추가한 알 수 없는 필드 제거 (forward compatibility)

### Transformer 함수

```typescript
interface IDeviceStatus {
  deviceId: string;
  workspaceId: string;
  timestamp: Date;
  temperature: number | null;
  fanSpeed: number | null;
  cpuUsage: number | null;
}

export function transformDeviceStatus(raw: any): IDeviceStatus {
  return {
    deviceId: raw.device_id,
    workspaceId: raw.workspace_id,
    timestamp: new Date(raw.timestamp),
    temperature: raw.metrics.temperature,
    fanSpeed: raw.metrics.fan_speed,
    cpuUsage: raw.metrics.cpu_usage,
  };
}
```

### Consumer에서 사용

```typescript
async function processMessages(messages: Array<{ value: unknown }>): Promise<void> {
  let processed = 0;
  let validationFailed = 0;

  for (const msg of messages) {
    // Step 1: Validate
    const { error, value } = deviceStatusSchema.validate(msg.value);
    if (error) {
      validationFailed++;
      logger.warn('Validation failed', {
        errors: error.details.map((d) => d.message),
        raw: JSON.stringify(msg.value).slice(0, 500),
      });
      continue; // skip invalid message
    }

    // Step 2: Transform
    const status = transformDeviceStatus(value);

    // Step 3: Handle
    await handleDeviceStatus(status);
    processed++;
  }

  logger.info('Batch processed', { processed, validationFailed, total: messages.length });
}
```

---

## Zod 기반 패턴

```typescript
import { z } from 'zod';

export const deviceStatusSchema = z.object({
  device_id: z.string(),
  workspace_id: z.string(),
  timestamp: z.string().datetime(),
  metrics: z.object({
    temperature: z.number().nullable(),
    fan_speed: z.number().nullable(),
    cpu_usage: z.number().min(0).max(100).nullable(),
  }),
  firmware_version: z.string().optional(),
}).passthrough(); // 추가 필드 허용 (stripUnknown 대체)

// Transform은 Zod의 .transform()으로 체이닝 가능
export const deviceStatusTransform = deviceStatusSchema.transform((raw) => ({
  deviceId: raw.device_id,
  workspaceId: raw.workspace_id,
  timestamp: new Date(raw.timestamp),
  temperature: raw.metrics.temperature,
  fanSpeed: raw.metrics.fan_speed,
  cpuUsage: raw.metrics.cpu_usage,
}));

// 사용
const result = deviceStatusTransform.safeParse(msg.value);
if (!result.success) {
  logger.warn('Validation failed', { errors: result.error.issues });
  continue;
}
const status = result.data; // 이미 변환된 도메인 모델
```

---

## Joi vs Zod 선택 기준

| 기준 | Joi | Zod |
|------|-----|-----|
| 타입 추론 | ❌ 별도 인터페이스 필요 | ✅ `z.infer<typeof schema>` |
| Transform 통합 | ❌ 별도 함수 | ✅ `.transform()` 체이닝 |
| 번들 사이즈 | 크다 (~150KB) | 작다 (~50KB) |
| 에러 메시지 커스텀 | ✅ 매우 유연 | ○ 충분 |
| stripUnknown | ✅ 옵션 하나로 | `.strict()` / `.passthrough()` |
| 생태계 | Express/Hapi에서 오래 사용 | 최근 빠르게 성장 |
| 기존 프로젝트 | 이미 Joi 쓰고 있으면 유지 | 새 프로젝트면 Zod 권장 |

**결론:** 기존 프로젝트가 Joi면 Joi 유지. 새로 시작하면 Zod (타입 추론 + transform 체이닝).

---

## Validation 실패 처리 전략

| 전략 | 설명 | 적합 |
|------|------|------|
| **Skip + Warn** | 로그 남기고 무시 | 비필수 이벤트, 허용 가능한 유실 |
| **DLQ 라우팅** | 별도 topic/queue로 이동 후 수동 처리 | 유실 불가, 데이터 정합성 중요 |
| **Retry** | N회 재시도 후 DLQ | 일시적 파싱 문제 (스키마 전환 과도기) |
| **Throw (halt)** | Consumer 중단 | 절대 안 됨 (다른 메시지까지 블록) |

**실전 가이드:**
- 대부분의 경우 **Skip + Warn** + 모니터링 알림으로 충분
- 금융/결제 이벤트처럼 유실 불가한 경우만 DLQ
- Throw는 절대 하지 않음 — 하나의 잘못된 메시지가 전체 consumer를 멈춤

---

## Schema Versioning

### Event Envelope에 version 포함

```typescript
interface IEventEnvelope<T> {
  event_id: string;
  event_type: string;
  schema_version: number; // 1, 2, 3...
  payload: T;
}
```

### Version별 분기 처리

```typescript
function validateByVersion(envelope: IEventEnvelope<unknown>) {
  switch (envelope.schema_version) {
    case 1: return deviceStatusSchemaV1.validate(envelope.payload);
    case 2: return deviceStatusSchemaV2.validate(envelope.payload);
    default:
      logger.warn('Unknown schema version', { version: envelope.schema_version });
      return deviceStatusSchemaV2.validate(envelope.payload); // 최신으로 fallback
  }
}
```

### Upcasting (구 버전 → 현재 버전 변환)

```typescript
function upcastV1toV2(v1: DeviceStatusV1): DeviceStatusV2 {
  return {
    ...v1,
    metrics: {
      temperature: v1.temperature, // v1은 flat, v2는 nested
      fan_speed: v1.fan_speed,
      cpu_usage: null, // v2에서 추가된 필드 — default값
    },
  };
}
```

---

## 테스트 패턴

```typescript
describe('deviceStatusSchema', () => {
  it('should accept valid payload', () => {
    const valid = { device_id: 'dev-001', workspace_id: 'ws-001', timestamp: '2026-01-01T00:00:00Z', metrics: { temperature: 25, fan_speed: 500, cpu_usage: 45 } };
    const { error } = deviceStatusSchema.validate(valid);
    expect(error).toBeUndefined();
  });

  it('should reject missing required field', () => {
    const invalid = { workspace_id: 'ws-001', timestamp: '2026-01-01T00:00:00Z', metrics: {} };
    const { error } = deviceStatusSchema.validate(invalid);
    expect(error).toBeDefined();
    expect(error!.details.some((d) => d.path.includes('device_id'))).toBe(true);
  });

  it('should strip unknown fields', () => {
    const extra = { device_id: 'dev-001', workspace_id: 'ws-001', timestamp: '2026-01-01T00:00:00Z', metrics: { temperature: 25, fan_speed: null, cpu_usage: null }, unknown_field: 'should be removed' };
    const { value } = deviceStatusSchema.validate(extra);
    expect(value).not.toHaveProperty('unknown_field');
  });

  it('should allow null for nullable fields', () => {
    const nullable = { device_id: 'dev-001', workspace_id: 'ws-001', timestamp: '2026-01-01T00:00:00Z', metrics: { temperature: null, fan_speed: null, cpu_usage: null } };
    const { error } = deviceStatusSchema.validate(nullable);
    expect(error).toBeUndefined();
  });
});
```

---

## 관련 스킬 참조
- `contract-testing` — Producer fixture vs Consumer schema 계약 테스트
- `nodejs-kafka` (계획 중) — Kafka consumer 전체 패턴
