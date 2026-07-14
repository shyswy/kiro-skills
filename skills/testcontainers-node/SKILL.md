---
name: testcontainers-node
description: |
  Testcontainers로 Node.js 통합 테스트 환경(PostgreSQL, OpenSearch, Kafka)을 구축하는 패턴 가이드.
  컨테이너 lifecycle 관리, Jest 연동, 테스트 격리, DDL 로드, CI 환경 대응을 다룬다.
  단위 테스트가 아닌 외부 인프라 의존 통합 테스트(component test, service test) 작성 시 사용.
  트리거: testcontainers, 통합 테스트 환경, docker 테스트, 컨테이너 테스트, component test,
  postgresql testcontainer, kafka testcontainer, opensearch testcontainer,
  integration test setup, 테스트 DB, 테스트 컨테이너
license: MIT
---

# Testcontainers Node.js Patterns

## 개요

Testcontainers는 테스트용 Docker 컨테이너를 코드에서 관리하는 라이브러리.
실제 DB/메시징/검색엔진을 띄워서 테스트하므로 mock보다 신뢰도 높은 통합 테스트가 가능.

**언제 사용:**
- Repository/DAO 레이어 테스트 (실제 SQL 실행)
- Kafka consumer/producer 통합 테스트
- OpenSearch 인덱스/쿼리 테스트
- Component test (모듈 전체를 실제 인프라와 연동)

**언제 사용하지 않음:**
- 순수 비즈니스 로직 단위 테스트 → mock으로 충분
- CI에서 Docker 사용 불가한 환경

---

## PostgreSQL

### 기본 설정

```typescript
import { PostgreSqlContainer, StartedPostgreSqlContainer } from '@testcontainers/postgresql';
import { Pool } from 'pg';

let container: StartedPostgreSqlContainer;
let pool: Pool;

beforeAll(async () => {
  container = await new PostgreSqlContainer('postgres:16')
    .withDatabase('test_db')
    .withUsername('test')
    .withPassword('test')
    .start();

  pool = new Pool({
    host: container.getHost(),
    port: container.getPort(),
    database: container.getDatabase(),
    user: container.getUsername(),
    password: container.getPassword(),
  });
}, 30_000); // 컨테이너 시작 시간 여유

afterAll(async () => {
  await pool.end();
  await container.stop();
});
```

### DDL 로드 (Ground Truth 스키마)

```typescript
import * as fs from 'fs';
import * as path from 'path';

async function applyDDL(pool: Pool, sqlPaths: string[]): Promise<void> {
  for (const sqlPath of sqlPaths) {
    const fullPath = path.resolve(__dirname, '../../../db/modules', sqlPath);
    const ddl = fs.readFileSync(fullPath, 'utf-8');
    await pool.query(ddl);
  }
}

// 사용
beforeAll(async () => {
  // ... container 시작 후
  await applyDDL(pool, [
    'monitoring/threshold_setting.sql',
    'monitoring/incident_history.sql',
  ]);
});
```

**Ground Truth 원칙:** DDL 파일은 `db/modules/` (실제 마이그레이션 소스)에서 직접 로드.
테스트 전용 DDL 따로 관리하면 실제 스키마와 분리될 위험.

### Seed 데이터

```typescript
async function seedTestData(pool: Pool): Promise<void> {
  await pool.query(`
    INSERT INTO threshold_settings (device_type, issue_code, threshold_value, is_active)
    VALUES ('display', 'TEM-01', 70, true),
           ('display', 'FAN-01', 1000, true)
  `);
}
```

---

## OpenSearch

```typescript
import { ElasticsearchContainer, StartedElasticsearchContainer } from '@testcontainers/elasticsearch';
import { Client } from '@opensearch-project/opensearch';

let esContainer: StartedElasticsearchContainer;
let osClient: Client;

beforeAll(async () => {
  esContainer = await new ElasticsearchContainer('opensearchproject/opensearch:2.11.0')
    .withEnvironment({
      'discovery.type': 'single-node',
      'plugins.security.disabled': 'true',
      'OPENSEARCH_INITIAL_ADMIN_PASSWORD': 'TestPass123!',
    })
    .withStartupTimeout(60_000)
    .start();

  osClient = new Client({
    node: `http://${esContainer.getHost()}:${esContainer.getMappedPort(9200)}`,
  });

  // 인덱스 생성
  await osClient.indices.create({
    index: 'test-incidents',
    body: { mappings: { properties: { device_id: { type: 'keyword' } } } },
  });
}, 60_000);

afterAll(async () => {
  await esContainer?.stop();
});
```

**주의:** `@testcontainers/elasticsearch`를 사용하되 OpenSearch 이미지를 지정. API 호환.

---

## Kafka

```typescript
import { KafkaContainer, StartedKafkaContainer } from '@testcontainers/kafka';
import { Kafka, Producer, Consumer } from 'kafkajs';

let kafkaContainer: StartedKafkaContainer;
let kafka: Kafka;

beforeAll(async () => {
  kafkaContainer = await new KafkaContainer('confluentinc/cp-kafka:7.5.0')
    .withExposedPorts(9093)
    .start();

  kafka = new Kafka({
    brokers: [`${kafkaContainer.getHost()}:${kafkaContainer.getMappedPort(9093)}`],
  });
}, 60_000);

afterAll(async () => {
  await kafkaContainer?.stop();
});

// Topic 생성
async function createTopic(topicName: string): Promise<void> {
  const admin = kafka.admin();
  await admin.connect();
  await admin.createTopics({ topics: [{ topic: topicName, numPartitions: 1 }] });
  await admin.disconnect();
}
```

---

## Jest 설정 패턴

### Global Setup/Teardown (권장하지 않음)

테스트 간 격리가 어렵고 디버깅 복잡. **describe-level** 관리를 권장.

### describe-level (권장)

```typescript
describe('ThresholdSettingRepository', () => {
  let container: StartedPostgreSqlContainer;
  let pool: Pool;
  let repo: ThresholdSettingRepository;

  beforeAll(async () => {
    container = await new PostgreSqlContainer('postgres:16').start();
    pool = new Pool({ /* ... */ });
    await applyDDL(pool, ['monitoring/threshold_setting.sql']);
    repo = new ThresholdSettingRepository(pool);
  }, 30_000);

  afterAll(async () => {
    await pool.end();
    await container.stop();
  });

  beforeEach(async () => {
    await pool.query('TRUNCATE threshold_settings CASCADE');
  });

  it('should insert and retrieve settings', async () => {
    // ...
  });
});
```

### Jest config

```typescript
// jest.config.ts (component test용)
export default {
  testMatch: ['**/*.comp.spec.ts'],
  testTimeout: 60_000, // 컨테이너 시작 시간 고려
  maxWorkers: 1, // 컨테이너 병렬 시작 시 리소스 부족 방지
};
```

---

## 테스트 격리 전략

| 방식 | 장점 | 단점 | 적합 |
|------|------|------|------|
| `beforeEach` + TRUNCATE | 빠름, 격리 확실 | DDL 변경 시 CASCADE 복잡 | 대부분의 경우 |
| 컨테이너 재시작 | 완벽한 격리 | 느림 (30초+) | DB 상태 자체가 테스트 대상일 때 |
| Transaction rollback | 매우 빠름 | 트랜잭션 내 동작만 테스트 가능 | 단순 CRUD |

---

## CI 환경 주의사항

```yaml
# GitLab CI
test:component:
  image: node:24
  services:
    - docker:dind
  variables:
    DOCKER_HOST: tcp://docker:2375
    TESTCONTAINERS_RYUK_DISABLED: 'true'  # DinD에서 Ryuk 불안정
  script:
    - npm run test:component
```

**Docker-in-Docker 이슈:**
- `TESTCONTAINERS_RYUK_DISABLED=true`: DinD 환경에서 Ryuk 컨테이너 충돌 방지
- `DOCKER_HOST` 환경변수로 DinD 소켓 지정
- 타임아웃 여유있게 설정 (이미지 pull 시간)

---

## 관련 스킬 참조
- `nodejs-typescript` — Node.js 테스트 일반 (node:test, 단위 테스트)
- `opensearch-node` — OpenSearch 클라이언트 패턴
- `pg-raw-query-patterns` — PostgreSQL raw query 패턴
