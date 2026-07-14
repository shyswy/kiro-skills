---
name: opensearch-node
description: |
  OpenSearch Node.js 클라이언트(@opensearch-project/opensearch) TypeScript 구현 패턴 가이드.
  클라이언트 설정, AWS SigV4/Basic Auth 인증, 인덱스 관리, CRUD, 검색 쿼리, Bulk 작업,
  Testcontainers 통합 테스트를 다룬다. elasticsearch-opensearch 스킬이 인프라/쿼리 튜닝 레벨이라면,
  이 스킬은 Node.js 코드로 "어떻게 구현하는가"에 집중한다.
  트리거: opensearch client, opensearch node, opensearch typescript, bulk index node,
  sigv4 opensearch, opensearch 연동, opensearch sdk, 오픈서치 노드, 오픈서치 클라이언트,
  opensearch jest test, opensearch testcontainers
license: MIT
---

# OpenSearch Node.js Client Patterns

## 클라이언트 설정

### AWS SigV4 인증 (Production — EKS/IRSA)

```typescript
import { Client } from '@opensearch-project/opensearch';
import { AwsSigv4Signer } from '@opensearch-project/opensearch/aws';
import { defaultProvider } from '@aws-sdk/credential-provider-node';

function createProductionClient(): Client {
  const node = process.env.OPENSEARCH_ENDPOINT;
  const region = process.env.AWS_REGION || 'ap-northeast-2';

  if (!node) throw new Error('OPENSEARCH_ENDPOINT is required');

  return new Client({
    ...AwsSigv4Signer({
      region,
      service: 'es', // managed OpenSearch. 'aoss' for Serverless
      getCredentials: () => defaultProvider()(),
    }),
    node,
  });
}
```

### Basic Auth (로컬 개발 / Docker)

```typescript
function createLocalClient(): Client {
  return new Client({
    node: process.env.OPENSEARCH_NODE || 'https://localhost:9200',
    auth: {
      username: process.env.OPENSEARCH_USERNAME || 'admin',
      password: process.env.OPENSEARCH_PASSWORD || 'admin',
    },
    ssl: { rejectUnauthorized: false },
  });
}
```

### 환경 자동 분기 팩토리

```typescript
let instance: Client | null = null;

export function getOpenSearchClient(): Client {
  if (instance) return instance;

  const hasBasicAuth = process.env.OPENSEARCH_USERNAME && process.env.OPENSEARCH_PASSWORD;
  instance = hasBasicAuth ? createLocalClient() : createProductionClient();
  return instance;
}
```

**싱글턴 패턴 이유**: OpenSearch 클라이언트는 내부 connection pool 관리. 인스턴스 여러 개 만들면 커넥션 낭비.

---

## 인덱스 관리

### Index Template 생성

```typescript
async function createIndexTemplate(client: Client, name: string, pattern: string, mappings: object): Promise<void> {
  await client.indices.putIndexTemplate({
    name,
    body: {
      index_patterns: [pattern],
      template: {
        settings: {
          number_of_shards: 2,
          number_of_replicas: 1,
        },
        mappings: { properties: mappings },
      },
    },
  });
}
```

### Index 존재 확인 + 생성

```typescript
async function ensureIndex(client: Client, index: string, mappings: object): Promise<void> {
  const exists = await client.indices.exists({ index });
  if (exists.body) return;

  await client.indices.create({
    index,
    body: {
      settings: { number_of_shards: 2, number_of_replicas: 1 },
      mappings: { properties: mappings },
    },
  });
}
```

### Index Naming Convention

```typescript
// 환경별 prefix + 도메인 + 날짜 (time-series)
const indexName = `${env}-incidents-${format(new Date(), 'yyyy.MM')}`;
// 예: prod-incidents-2026.07, dev-incidents-2026.07

// Alias 사용 (검색 시)
const readAlias = `${env}-incidents-read`;  // 모든 월별 인덱스 커버
const writeAlias = `${env}-incidents-write`; // 현재 월 인덱스만
```

---

## CRUD 패턴

### Document Indexing (단건)

```typescript
interface IIncident {
  incident_id: string;
  device_id: string;
  issue_code: string;
  status: 'open' | 'resolved';
  occurred_at: string;
}

async function indexIncident(client: Client, index: string, doc: IIncident): Promise<string> {
  const response = await client.index({
    index,
    id: doc.incident_id, // 자연키 사용 (upsert 가능)
    body: doc,
    refresh: 'wait_for', // 즉시 검색 가능하게 (테스트용. 프로덕션은 false)
  });
  return response.body._id;
}
```

### Bulk Indexing (배치)

```typescript
async function bulkIndex(client: Client, index: string, docs: IIncident[]): Promise<{ success: number; failed: number }> {
  if (docs.length === 0) return { success: 0, failed: 0 };

  const body = docs.flatMap((doc) => [
    { index: { _index: index, _id: doc.incident_id } },
    doc,
  ]);

  const response = await client.bulk({ body, refresh: false });

  let failed = 0;
  if (response.body.errors) {
    for (const item of response.body.items) {
      if (item.index?.error) {
        failed++;
        // 429 (Too Many Requests) → retry 대상
        // 400 (Bad Request) → 데이터 문제, skip
      }
    }
  }

  return { success: docs.length - failed, failed };
}
```

**Bulk 주의사항:**
- 한 번에 5MB~15MB 이하로 보내기 (OpenSearch 권장)
- 429 에러 시 exponential backoff 후 재시도
- `refresh: false`로 보내고 마지막에 `_refresh` API 한번 호출 (성능)

### Search 쿼리

```typescript
interface ISearchParams {
  deviceId?: string;
  status?: string;
  from?: string;
  to?: string;
  page?: number;
  size?: number;
}

async function searchIncidents(client: Client, index: string, params: ISearchParams) {
  const must: object[] = [];

  if (params.deviceId) must.push({ term: { device_id: params.deviceId } });
  if (params.status) must.push({ term: { status: params.status } });
  if (params.from || params.to) {
    must.push({
      range: {
        occurred_at: {
          ...(params.from && { gte: params.from }),
          ...(params.to && { lte: params.to }),
        },
      },
    });
  }

  const response = await client.search({
    index,
    body: {
      query: must.length > 0 ? { bool: { must } } : { match_all: {} },
      sort: [{ occurred_at: { order: 'desc' } }],
      from: ((params.page || 1) - 1) * (params.size || 20),
      size: params.size || 20,
    },
  });

  return {
    total: response.body.hits.total.value,
    hits: response.body.hits.hits.map((hit: any) => hit._source),
  };
}
```

### Update (Partial)

```typescript
async function updateIncidentStatus(client: Client, index: string, id: string, status: string): Promise<void> {
  await client.update({
    index,
    id,
    body: {
      doc: { status, resolved_at: new Date().toISOString() },
    },
    retry_on_conflict: 3,
  });
}
```

---

## 에러 핸들링

```typescript
import { ResponseError } from '@opensearch-project/opensearch/lib/errors';

async function safeSearch(client: Client, index: string, query: object) {
  try {
    return await client.search({ index, body: { query } });
  } catch (error) {
    if (error instanceof ResponseError) {
      const status = error.meta.statusCode;
      if (status === 404) return null; // 인덱스 없음
      if (status === 403) throw new Error('OpenSearch access denied (check IAM/SigV4)');
      if (status === 429) throw new Error('OpenSearch throttled (too many requests)');
    }
    throw error;
  }
}
```

---

## 연결 확인 (Health Check)

```typescript
async function pingOpenSearch(client: Client): Promise<boolean> {
  try {
    const response = await client.info();
    console.log('Connected:', response.body.cluster_name, response.body.version.number);
    return true;
  } catch (error: any) {
    console.error('OpenSearch connection failed:', {
      status: error?.meta?.statusCode,
      message: error?.message,
    });
    return false;
  }
}
```

`GET /` (info)를 사용하는 이유: `HEAD /` (ping)은 403에서 body를 반환 안 해서 디버깅 어려움.

---

## Testcontainers 통합 테스트

```typescript
import { ElasticsearchContainer, StartedElasticsearchContainer } from '@testcontainers/elasticsearch';
import { Client } from '@opensearch-project/opensearch';

let container: StartedElasticsearchContainer;
let client: Client;

beforeAll(async () => {
  container = await new ElasticsearchContainer('opensearchproject/opensearch:2.11.0')
    .withEnvironment({
      'discovery.type': 'single-node',
      'plugins.security.disabled': 'true',
    })
    .start();

  client = new Client({
    node: `http://${container.getHost()}:${container.getMappedPort(9200)}`,
  });
}, 60_000);

afterAll(async () => {
  await container?.stop();
});
```

---

## 관련 스킬 참조
- `elasticsearch-opensearch` — 인덱스 설계, 매핑, 쿼리 튜닝, ILM (인프라 레벨)
- `nodejs-typescript` — Node.js 범용 패턴 (error handling, graceful shutdown)
