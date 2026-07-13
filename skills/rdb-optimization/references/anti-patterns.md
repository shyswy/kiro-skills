# SQL Anti-Patterns

## 쿼리 Anti-Patterns

### 1. SELECT *
```sql
-- Bad
SELECT * FROM orders WHERE user_id = 123;

-- Good: 필요한 컬럼만
SELECT id, status, total, created_at FROM orders WHERE user_id = 123;
```
문제: 불필요한 I/O, covering index 활용 불가, 스키마 변경 시 깨짐

### 2. N+1 쿼리
```sql
-- Bad: 루프 내 쿼리 (ORM에서 흔함)
for user in users:
    orders = SELECT * FROM orders WHERE user_id = user.id;

-- Good: JOIN 또는 IN
SELECT u.*, o.* FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE u.id IN (1, 2, 3, ...);

-- Good: 배치 로딩
SELECT * FROM orders WHERE user_id IN (1, 2, 3, ...);
```

### 3. Implicit Type Cast
```sql
-- Bad: varchar 컬럼에 숫자 비교 → 인덱스 무효
SELECT * FROM users WHERE phone = 01012345678;

-- Good: 타입 일치
SELECT * FROM users WHERE phone = '01012345678';

-- Bad: date 컬럼에 문자열 함수
SELECT * FROM orders WHERE CAST(created_at AS TEXT) LIKE '2026-05%';

-- Good: 범위 조건
SELECT * FROM orders WHERE created_at >= '2026-05-01' AND created_at < '2026-06-01';
```

### 4. OR 남용
```sql
-- Bad: 복합 인덱스 활용 불가
SELECT * FROM orders WHERE status = 'active' OR status = 'pending' OR user_id = 123;

-- Good: IN으로 변환 (같은 컬럼)
SELECT * FROM orders WHERE status IN ('active', 'pending');

-- Good: UNION ALL (다른 컬럼)
SELECT * FROM orders WHERE status IN ('active', 'pending')
UNION ALL
SELECT * FROM orders WHERE user_id = 123 AND status NOT IN ('active', 'pending');
```

### 5. 함수로 감싼 인덱스 컬럼
```sql
-- Bad: 인덱스 무효
SELECT * FROM users WHERE LOWER(email) = 'user@example.com';
SELECT * FROM orders WHERE YEAR(created_at) = 2026;
SELECT * FROM orders WHERE created_at + INTERVAL '7 days' > NOW();

-- Good: 값 쪽을 변환
SELECT * FROM users WHERE email = 'user@example.com';  -- 저장 시 lowercase
SELECT * FROM orders WHERE created_at >= '2026-01-01' AND created_at < '2027-01-01';
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '7 days';
```

### 6. DISTINCT 남용
```sql
-- Bad: JOIN 잘못으로 중복 발생 → DISTINCT로 숨김
SELECT DISTINCT u.id, u.name FROM users u
JOIN orders o ON o.user_id = u.id;

-- Good: EXISTS로 중복 없이
SELECT u.id, u.name FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

### 7. NOT IN with NULL
```sql
-- Bad: subquery에 NULL 포함 시 결과 0건
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
-- blacklist.user_id에 NULL이 하나라도 있으면 전체 결과 empty!

-- Good: NOT EXISTS
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM blacklist b WHERE b.user_id = u.id);
```

---

## 설계 Anti-Patterns

### 8. EAV (Entity-Attribute-Value)
```sql
-- Bad: 유연하지만 쿼리 복잡, 인덱스 비효율
CREATE TABLE attributes (
    entity_id int, attribute_name text, attribute_value text
);

-- Good: JSONB (PostgreSQL) 또는 정규화된 컬럼
CREATE TABLE products (
    id int, name text, specs jsonb
);
```

### 9. 과도한 정규화
```sql
-- Bad: 단순 조회에 5개 테이블 JOIN 필요
SELECT p.name, c.name, s.name, ...
FROM products p
JOIN categories c ON ...
JOIN subcategories s ON ...
JOIN brands b ON ...
JOIN suppliers sp ON ...;

-- Good: 읽기 빈도 높으면 비정규화 또는 materialized view
CREATE MATERIALIZED VIEW product_summary AS
SELECT p.id, p.name, c.name as category, b.name as brand
FROM products p JOIN categories c ON ... JOIN brands b ON ...;
```

### 10. Soft Delete 무분별 사용
```sql
-- 문제: 모든 쿼리에 WHERE deleted_at IS NULL 필요, 인덱스 비효율
SELECT * FROM users WHERE email = 'a@b.com' AND deleted_at IS NULL;

-- 대안 1: Partial Index
CREATE INDEX idx_users_email_active ON users (email) WHERE deleted_at IS NULL;

-- 대안 2: 아카이브 테이블 분리
-- 삭제 시 users → users_archive로 이동
```

---

## 트랜잭션 Anti-Patterns

### 11. 긴 트랜잭션
```sql
-- Bad: 외부 API 호출을 트랜잭션 안에서
BEGIN;
UPDATE orders SET status = 'processing' WHERE id = 1;
-- ... 외부 결제 API 호출 (3초) ...
UPDATE orders SET status = 'paid' WHERE id = 1;
COMMIT;

-- Good: 트랜잭션 최소화
UPDATE orders SET status = 'processing' WHERE id = 1;
-- 외부 API 호출
BEGIN;
UPDATE orders SET status = 'paid' WHERE id = 1;
INSERT INTO payments (...) VALUES (...);
COMMIT;
```

### 12. Lock 순서 불일치 → Deadlock
```sql
-- Transaction A: users → orders 순서
BEGIN; UPDATE users SET ... WHERE id = 1; UPDATE orders SET ... WHERE id = 10; COMMIT;

-- Transaction B: orders → users 순서 (역순!)
BEGIN; UPDATE orders SET ... WHERE id = 10; UPDATE users SET ... WHERE id = 1; COMMIT;

-- Good: 항상 같은 순서로 접근
-- 규칙: users → orders → payments (알파벳 순 등 일관된 규칙)
```

### 13. SELECT FOR UPDATE 남용
```sql
-- Bad: 불필요한 행 잠금
SELECT * FROM products WHERE category = 'electronics' FOR UPDATE;
-- 카테고리 전체를 잠금!

-- Good: 필요한 행만, 짧게
SELECT * FROM products WHERE id = 123 FOR UPDATE NOWAIT;
-- NOWAIT: 잠금 실패 시 즉시 에러 (대기 안 함)
-- SKIP LOCKED: 잠긴 행 건너뛰기 (큐 패턴)
```

---

## ORM Anti-Patterns

### 14. Lazy Loading in Loop
```typescript
// Bad: N+1 (TypeORM)
const users = await userRepo.find();
for (const user of users) {
  const orders = await user.orders;  // 매번 쿼리 발생
}

// Good: Eager loading
const users = await userRepo.find({ relations: ['orders'] });

// Good: QueryBuilder
const users = await userRepo
  .createQueryBuilder('user')
  .leftJoinAndSelect('user.orders', 'order')
  .getMany();
```

### 15. ORM 생성 쿼리 무검증
```typescript
// ORM이 생성하는 쿼리를 반드시 확인
// TypeORM: logging: true
// Prisma: prisma.$on('query', ...)
// Sequelize: logging: console.log
```

항상 개발 환경에서 ORM 쿼리 로그를 켜고, 느린 쿼리를 EXPLAIN으로 확인할 것.
