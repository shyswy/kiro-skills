---
name: pg-raw-query-patterns
description: |
  Node.js pg 라이브러리로 PostgreSQL raw query를 타입 안전하게 작성하는 패턴 가이드.
  Pool 관리, Parameterized query, Transaction, Repository 패턴, Bulk insert/upsert,
  결과 타입 매핑을 다룬다. ORM(TypeORM/Prisma)을 사용하지 않는 프로젝트에서 적용.
  트리거: pg query, raw sql node, postgresql node, parameterized query, pg pool,
  bulk insert pg, pg transaction, node postgres, sql injection prevention node
license: MIT
---

# PostgreSQL Raw Query Patterns (Node.js pg)

## Pool 설정

```typescript
import { Pool, PoolConfig } from 'pg';

const poolConfig: PoolConfig = {
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20,                    // 최대 커넥션 수
  idleTimeoutMillis: 30_000,  // idle 커넥션 해제까지 30초
  connectionTimeoutMillis: 5_000, // 커넥션 획득 타임아웃
};

// Search path 설정 (multi-schema)
if (process.env.DB_SCHEMA) {
  poolConfig.options = `-c search_path=${process.env.DB_SCHEMA}`;
}

const pool = new Pool(poolConfig);

// Pool 에러 핸들링 (필수 — 안 하면 process crash)
pool.on('error', (err) => {
  console.error('Unexpected pool error', err);
});
```

**max 설정 기준:**
- 컨테이너 1개당 max = (사용 가능한 DB 커넥션) / (Pod 수)
- RDS max_connections 기본값: 인스턴스 메모리 기반 (예: db.t3.medium = 82)
- RDS Proxy 사용 시 더 여유롭게 설정 가능

---

## Parameterized Query (SQL Injection 방지)

```typescript
// ✅ 올바른 방법 — $1, $2 바인딩
const result = await pool.query(
  'SELECT * FROM devices WHERE workspace_id = $1 AND status = $2',
  [workspaceId, 'active']
);

// ❌ 절대 하지 않음 — SQL Injection 취약
const result = await pool.query(
  `SELECT * FROM devices WHERE workspace_id = '${workspaceId}'`
);
```

**타입 안전 결과:**

```typescript
interface IDevice {
  device_id: string;
  workspace_id: string;
  device_type: string;
  status: string;
  created_at: Date;
}

const { rows } = await pool.query<IDevice>(
  'SELECT device_id, workspace_id, device_type, status, created_at FROM devices WHERE workspace_id = $1',
  [workspaceId]
);
// rows: IDevice[]
```

---

## Repository 패턴

```typescript
import { Pool } from 'pg';

export class ThresholdSettingRepository {
  constructor(private pool: Pool) {}

  async findByDeviceType(deviceType: string): Promise<IThresholdSetting[]> {
    const { rows } = await this.pool.query<IThresholdSettingRow>(
      `SELECT device_type, issue_code, threshold_value, is_active
       FROM threshold_settings
       WHERE device_type = $1 AND is_active = true`,
      [deviceType]
    );
    return rows.map(this.toDomain);
  }

  async upsert(setting: IThresholdSetting): Promise<void> {
    await this.pool.query(
      `INSERT INTO threshold_settings (device_type, issue_code, threshold_value, is_active)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (device_type, issue_code)
       DO UPDATE SET threshold_value = EXCLUDED.threshold_value, is_active = EXCLUDED.is_active`,
      [setting.deviceType, setting.issueCode, setting.thresholdValue, setting.isActive]
    );
  }

  private toDomain(row: IThresholdSettingRow): IThresholdSetting {
    return {
      deviceType: row.device_type,
      issueCode: row.issue_code,
      thresholdValue: row.threshold_value,
      isActive: row.is_active,
    };
  }
}
```

**snake_case → camelCase 매핑:** Repository 내부에서 `toDomain()` 메서드로 변환.
DB 레이어는 snake_case, 어플리케이션 레이어는 camelCase.

---

## Transaction

```typescript
import { Pool, PoolClient } from 'pg';

async function withTransaction<T>(pool: Pool, fn: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

// 사용
await withTransaction(pool, async (client) => {
  await client.query('INSERT INTO orders (id, total) VALUES ($1, $2)', [orderId, total]);
  await client.query('INSERT INTO order_items (order_id, product_id) VALUES ($1, $2)', [orderId, productId]);
});
```

**중요:** Transaction 내에서는 `pool.query()`가 아닌 `client.query()`를 사용.
`pool.query()`는 매번 다른 커넥션을 잡으므로 트랜잭션 범위 밖.

---

## Bulk Insert

### VALUES list 생성 패턴

```typescript
function buildBulkInsert(tableName: string, columns: string[], rows: any[][]): { text: string; values: any[] } {
  const values: any[] = [];
  const valueClauses: string[] = [];

  rows.forEach((row, rowIdx) => {
    const placeholders = row.map((_, colIdx) => `$${rowIdx * columns.length + colIdx + 1}`);
    valueClauses.push(`(${placeholders.join(', ')})`);
    values.push(...row);
  });

  const text = `INSERT INTO ${tableName} (${columns.join(', ')}) VALUES ${valueClauses.join(', ')}`;
  return { text, values };
}

// 사용
const devices = [
  ['dev-001', 'ws-001', 'display'],
  ['dev-002', 'ws-001', 'signage'],
];
const { text, values } = buildBulkInsert('devices', ['device_id', 'workspace_id', 'device_type'], devices);
await pool.query(text, values);
```

### Bulk Upsert (ON CONFLICT)

```typescript
function buildBulkUpsert(
  tableName: string,
  columns: string[],
  rows: any[][],
  conflictColumns: string[],
  updateColumns: string[]
): { text: string; values: any[] } {
  const { text: insertText, values } = buildBulkInsert(tableName, columns, rows);
  const conflictClause = `ON CONFLICT (${conflictColumns.join(', ')})`;
  const updateClause = updateColumns.map((col) => `${col} = EXCLUDED.${col}`).join(', ');

  return {
    text: `${insertText} ${conflictClause} DO UPDATE SET ${updateClause}`,
    values,
  };
}
```

**주의:** PostgreSQL은 한 쿼리에 65535개 파라미터 제한. Bulk insert 시 배치 분할:
```typescript
const BATCH_SIZE = 1000;
for (let i = 0; i < rows.length; i += BATCH_SIZE) {
  const batch = rows.slice(i, i + BATCH_SIZE);
  const { text, values } = buildBulkInsert('devices', columns, batch);
  await pool.query(text, values);
}
```

---

## Pagination

### Offset 기반 (간단, 대량 데이터에서 느림)

```typescript
async function findPaginated(pool: Pool, page: number, size: number): Promise<{ rows: IDevice[]; total: number }> {
  const offset = (page - 1) * size;

  const [dataResult, countResult] = await Promise.all([
    pool.query<IDevice>('SELECT * FROM devices ORDER BY created_at DESC LIMIT $1 OFFSET $2', [size, offset]),
    pool.query<{ count: string }>('SELECT COUNT(*) as count FROM devices'),
  ]);

  return { rows: dataResult.rows, total: parseInt(countResult.rows[0].count) };
}
```

### Cursor 기반 (대량 데이터에서 빠름)

```typescript
async function findAfterCursor(pool: Pool, cursor: string | null, size: number): Promise<{ rows: IDevice[]; nextCursor: string | null }> {
  const query = cursor
    ? 'SELECT * FROM devices WHERE created_at < $1 ORDER BY created_at DESC LIMIT $2'
    : 'SELECT * FROM devices ORDER BY created_at DESC LIMIT $1';

  const params = cursor ? [cursor, size + 1] : [size + 1];
  const { rows } = await pool.query<IDevice>(query, params);

  const hasNext = rows.length > size;
  const data = hasNext ? rows.slice(0, size) : rows;
  const nextCursor = hasNext ? data[data.length - 1].created_at.toISOString() : null;

  return { rows: data, nextCursor };
}
```

---

## Graceful Shutdown

```typescript
import closeWithGrace from 'close-with-grace';

closeWithGrace({ delay: 10_000 }, async () => {
  await pool.end(); // 모든 커넥션 반환 대기 후 종료
});
```

---

## 관련 스킬 참조
- `rdb-optimization` — EXPLAIN 분석, 인덱스 전략, 파티셔닝 (DBA 레벨)
- `testcontainers-node` — Testcontainers PG로 repository 테스트
- `nodejs-typescript` — Node.js 범용 패턴 (error handling, graceful shutdown)
