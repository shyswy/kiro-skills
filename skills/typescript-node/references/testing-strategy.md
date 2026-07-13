# 테스트 전략 상세

## 테스트 피라미드

```
        E2E (소수)
       /         \
    Integration (중간)
   /                 \
  Unit (다수, 빠름)
```

---

## Unit Test (Vitest)

### 기본 구조
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';

describe('OrderService', () => {
  let service: OrderService;
  let mockRepo: MockProxy<OrderRepository>;

  beforeEach(() => {
    mockRepo = mock<OrderRepository>();
    service = new OrderService(mockRepo);
  });

  it('should create order with valid data', async () => {
    mockRepo.save.mockResolvedValue(mockOrder);

    const result = await service.createOrder(validDto);

    expect(result).toEqual(mockOrder);
    expect(mockRepo.save).toHaveBeenCalledWith(expect.objectContaining({
      userId: validDto.userId,
      status: 'pending',
    }));
  });

  it('should throw ValidationError for invalid amount', async () => {
    await expect(service.createOrder({ ...validDto, amount: -1 }))
      .rejects.toThrow(ValidationError);
  });
});
```

### Mock 최소화 원칙
```typescript
// Bad: 모든 것을 mock (구현에 결합)
vi.mock('../utils/validator');
vi.mock('../utils/formatter');
vi.mock('../config');

// Good: 외부 의존성만 mock (DB, HTTP, 파일시스템)
// 내부 유틸은 실제 코드 사용
const mockRepo = mock<OrderRepository>();  // DB만 mock
```

### Parameterized Test
```typescript
it.each([
  { input: 'valid@email.com', expected: true },
  { input: 'invalid', expected: false },
  { input: '', expected: false },
  { input: 'a@b.c', expected: true },
])('validateEmail($input) should return $expected', ({ input, expected }) => {
  expect(validateEmail(input)).toBe(expected);
});
```

---

## Integration Test (Testcontainers)

### PostgreSQL
```typescript
import { PostgreSqlContainer, StartedPostgreSqlContainer } from '@testcontainers/postgresql';

describe('UserRepository (Integration)', () => {
  let container: StartedPostgreSqlContainer;
  let pool: Pool;
  let repo: UserRepository;

  beforeAll(async () => {
    container = await new PostgreSqlContainer('postgres:16-alpine')
      .withDatabase('testdb')
      .start();

    pool = new Pool({ connectionString: container.getConnectionUri() });
    await runMigrations(pool);  // 스키마 적용
    repo = new UserRepository(pool);
  }, 60000);

  afterAll(async () => {
    await pool.end();
    await container.stop();
  });

  afterEach(async () => {
    await pool.query('TRUNCATE users CASCADE');  // 테스트 간 격리
  });

  it('should insert and retrieve user', async () => {
    const user = await repo.create({ email: 'test@example.com', name: 'Test' });
    const found = await repo.findById(user.id);
    expect(found).toEqual(user);
  });
});
```

### Redis
```typescript
import { GenericContainer } from 'testcontainers';

let redisContainer: StartedTestContainer;
let redis: Redis;

beforeAll(async () => {
  redisContainer = await new GenericContainer('redis:7-alpine')
    .withExposedPorts(6379)
    .start();

  redis = new Redis({
    host: redisContainer.getHost(),
    port: redisContainer.getMappedPort(6379),
  });
});
```

### Kafka
```typescript
import { KafkaContainer } from '@testcontainers/kafka';

let kafkaContainer: StartedKafkaContainer;

beforeAll(async () => {
  kafkaContainer = await new KafkaContainer('confluentinc/cp-kafka:7.5.0')
    .withExposedPorts(9093)
    .start();

  const kafka = new Kafka({ brokers: [kafkaContainer.getBrokers()] });
});
```

---

## Fixture 관리

### Factory 패턴
```typescript
// factories/user.factory.ts
import { faker } from '@faker-js/faker';

export function buildUser(overrides: Partial<User> = {}): User {
  return {
    id: faker.string.uuid(),
    email: faker.internet.email(),
    name: faker.person.fullName(),
    createdAt: faker.date.recent(),
    ...overrides,
  };
}

export function buildOrder(overrides: Partial<Order> = {}): Order {
  return {
    id: faker.string.uuid(),
    userId: faker.string.uuid(),
    amount: faker.number.int({ min: 1000, max: 100000 }),
    status: 'pending',
    ...overrides,
  };
}

// 테스트에서 사용
const user = buildUser({ email: 'specific@test.com' });
const order = buildOrder({ userId: user.id, status: 'completed' });
```

### Seed 데이터
```typescript
// seeds/test-data.ts
export async function seedTestData(pool: Pool) {
  const users = Array.from({ length: 10 }, () => buildUser());
  await pool.query(
    `INSERT INTO users (id, email, name) VALUES ${users.map((_, i) => `($${i*3+1}, $${i*3+2}, $${i*3+3})`).join(',')}`,
    users.flatMap(u => [u.id, u.email, u.name])
  );
  return users;
}
```

---

## E2E Test (Supertest)

```typescript
import request from 'supertest';
import { app } from '../src/app';

describe('POST /api/users', () => {
  it('should create user and return 201', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ email: 'new@test.com', name: 'New User' })
      .expect(201);

    expect(response.body.data).toMatchObject({
      email: 'new@test.com',
      name: 'New User',
    });
    expect(response.body.data.id).toBeDefined();
  });

  it('should return 422 for invalid email', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ email: 'invalid', name: 'Test' })
      .expect(422);

    expect(response.body.error.code).toBe('VALIDATION_ERROR');
  });
});
```

---

## 테스트 설정 (vitest.config.ts)

```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['src/**/*.spec.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      exclude: ['**/*.spec.ts', '**/index.ts', '**/types/**'],
    },
    // Integration 테스트 분리
    typecheck: { enabled: true },
  },
});
```

### 스크립트 분리
```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:unit": "vitest run --include 'src/**/*.spec.ts' --exclude '**/*.integration.spec.ts'",
    "test:integration": "vitest run --include '**/*.integration.spec.ts'",
    "test:e2e": "vitest run --include 'test/e2e/**/*.spec.ts'",
    "test:coverage": "vitest run --coverage"
  }
}
```
