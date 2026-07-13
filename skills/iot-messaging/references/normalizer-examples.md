# Normalizer 구현 예제

## 정규화 아키텍처

```
디바이스 A (JSON) ─┐
디바이스 B (Binary)─┼→ Normalizer → 표준 이벤트 → Kafka/DB
디바이스 C (CSV)  ─┘
```

---

## 표준 이벤트 포맷

```typescript
interface NormalizedEvent {
  deviceId: string;
  deviceType: string;
  timestamp: string;        // ISO 8601
  reportType: 'full' | 'diff' | 'snapshot';
  metrics: Record<string, MetricValue>;
  metadata?: Record<string, string>;
}

interface MetricValue {
  value: number | string | boolean;
  unit?: string;
  quality?: 'good' | 'uncertain' | 'bad';
}
```

---

## 디바이스 타입별 Normalizer

### TV (webOS)
```typescript
// 입력: webOS 디바이스 리포트
interface WebOSTVReport {
  duid: string;
  model: string;
  fw_ver: string;
  status: {
    power: 'on' | 'off' | 'standby';
    input: string;
    volume: number;
    channel?: string;
  };
  diagnostics?: {
    cpu_usage: number;
    memory_free: number;
    uptime_hours: number;
    temperature: number;
  };
}

function normalizeWebOSTV(raw: WebOSTVReport): NormalizedEvent {
  return {
    deviceId: raw.duid,
    deviceType: 'webos-tv',
    timestamp: new Date().toISOString(),
    reportType: 'full',
    metrics: {
      power_state: { value: raw.status.power },
      current_input: { value: raw.status.input },
      volume: { value: raw.status.volume, unit: '%' },
      ...(raw.diagnostics && {
        cpu_usage: { value: raw.diagnostics.cpu_usage, unit: '%' },
        memory_free: { value: raw.diagnostics.memory_free, unit: 'MB' },
        uptime: { value: raw.diagnostics.uptime_hours, unit: 'hours' },
        temperature: { value: raw.diagnostics.temperature, unit: '°C' },
      }),
    },
    metadata: {
      model: raw.model,
      firmware: raw.fw_ver,
    },
  };
}
```

### 센서 디바이스 (MQTT Binary)
```typescript
// 입력: Binary payload (고정 길이)
// [deviceId:8bytes][timestamp:4bytes][temp:2bytes][humidity:2bytes][battery:1byte]

function normalizeSensor(buffer: Buffer, topic: string): NormalizedEvent {
  const deviceId = buffer.toString('utf8', 0, 8).trim();
  const timestamp = buffer.readUInt32BE(8) * 1000;  // epoch seconds → ms
  const temperature = buffer.readInt16BE(12) / 100;  // 0.01°C 단위
  const humidity = buffer.readUInt16BE(14) / 100;    // 0.01% 단위
  const battery = buffer.readUInt8(16);              // 0-100%

  return {
    deviceId,
    deviceType: 'sensor',
    timestamp: new Date(timestamp).toISOString(),
    reportType: 'full',
    metrics: {
      temperature: { value: temperature, unit: '°C' },
      humidity: { value: humidity, unit: '%' },
      battery: { value: battery, unit: '%', quality: battery < 10 ? 'uncertain' : 'good' },
    },
  };
}
```

### 에어컨 (JSON diff report)
```typescript
// 입력: 변경된 필드만 전송
interface ACDiffReport {
  id: string;
  ts: number;
  changed: {
    [key: string]: { old: any; new: any };
  };
}

function normalizeACDiff(raw: ACDiffReport): NormalizedEvent {
  const metrics: Record<string, MetricValue> = {};

  for (const [key, change] of Object.entries(raw.changed)) {
    metrics[key] = { value: change.new };
  }

  return {
    deviceId: raw.id,
    deviceType: 'air-conditioner',
    timestamp: new Date(raw.ts).toISOString(),
    reportType: 'diff',
    metrics,
  };
}
```

---

## Normalizer Registry 패턴

```typescript
type NormalizerFn = (raw: unknown, context?: NormalizerContext) => NormalizedEvent;

interface NormalizerContext {
  topic?: string;
  partition?: number;
  offset?: number;
}

class NormalizerRegistry {
  private normalizers = new Map<string, NormalizerFn>();

  register(deviceType: string, normalizer: NormalizerFn): void {
    this.normalizers.set(deviceType, normalizer);
  }

  normalize(deviceType: string, raw: unknown, context?: NormalizerContext): NormalizedEvent {
    const normalizer = this.normalizers.get(deviceType);
    if (!normalizer) {
      throw new Error(`No normalizer registered for device type: ${deviceType}`);
    }
    return normalizer(raw, context);
  }
}

// 사용
const registry = new NormalizerRegistry();
registry.register('webos-tv', normalizeWebOSTV);
registry.register('sensor', normalizeSensor);
registry.register('air-conditioner', normalizeACDiff);

// Kafka Consumer에서
const deviceType = detectDeviceType(message.topic, message.value);
const event = registry.normalize(deviceType, message.value);
await producer.send({ topic: 'normalized-events', messages: [{ value: JSON.stringify(event) }] });
```

---

## Diff → Full State 조합기

```typescript
class DeviceStateAggregator {
  private states = new Map<string, Record<string, MetricValue>>();

  apply(event: NormalizedEvent): NormalizedEvent {
    if (event.reportType === 'full' || event.reportType === 'snapshot') {
      // Full/Snapshot: 전체 상태 교체
      this.states.set(event.deviceId, { ...event.metrics });
    } else if (event.reportType === 'diff') {
      // Diff: 기존 상태에 변경분 병합
      const current = this.states.get(event.deviceId) || {};
      this.states.set(event.deviceId, { ...current, ...event.metrics });
    }

    // 현재 전체 상태 반환
    return {
      ...event,
      reportType: 'full',
      metrics: this.states.get(event.deviceId)!,
    };
  }

  getState(deviceId: string): Record<string, MetricValue> | undefined {
    return this.states.get(deviceId);
  }
}
```

---

## 에러 처리

```typescript
function safeNormalize(
  registry: NormalizerRegistry,
  deviceType: string,
  raw: unknown
): NormalizedEvent | null {
  try {
    const event = registry.normalize(deviceType, raw);
    // 필수 필드 검증
    if (!event.deviceId || !event.timestamp) {
      logger.warn('Missing required fields', { deviceType, raw });
      return null;
    }
    return event;
  } catch (error) {
    logger.error('Normalization failed', { deviceType, error, raw });
    // DLQ로 전송
    dlqProducer.send({
      topic: 'normalization-errors',
      messages: [{ value: JSON.stringify({ deviceType, raw, error: String(error) }) }],
    });
    return null;
  }
}
```
