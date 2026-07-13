# 인덱스 설계 전략

## 인덱스 타입별 선택 가이드

| 타입 | 용도 | DB |
|------|------|-----|
| B-tree | 등호, 범위, 정렬, LIKE 'prefix%' | PostgreSQL, MySQL (기본) |
| Hash | 등호 비교만 (범위 X) | PostgreSQL (제한적 사용) |
| GIN | 배열, JSONB, 전문검색 (tsvector) | PostgreSQL |
| GiST | 지리공간, 범위 타입, 전문검색 | PostgreSQL |
| BRIN | 물리적 정렬된 대용량 데이터 (시계열) | PostgreSQL |
| Full-text | 전문검색 | MySQL |

---

## 복합 인덱스 컬럼 순서 규칙

**ESR 규칙 (Equality → Sort → Range)**

```sql
-- 쿼리
SELECT * FROM orders
WHERE status = 'active'        -- Equality
  AND created_at > '2026-01-01' -- Range
ORDER BY total DESC;            -- Sort

-- 최적 인덱스
CREATE INDEX idx_orders_status_total_created
ON orders (status, total DESC, created_at);
-- 순서: Equality(status) → Sort(total) → Range(created_at)
```

**왜 이 순서인가:**
1. Equality 먼저: 결과셋을 최대한 줄임
2. Sort 다음: filesort 제거 (인덱스 순서 활용)
3. Range 마지막: 범위 조건 이후 컬럼은 인덱스 활용 불가

---

## Covering Index (Index Only Scan)

```sql
-- 쿼리가 필요한 모든 컬럼이 인덱스에 포함
SELECT user_id, status, created_at FROM orders WHERE user_id = 123;

-- Covering Index
CREATE INDEX idx_orders_covering
ON orders (user_id) INCLUDE (status, created_at);  -- PostgreSQL 11+

-- MySQL
CREATE INDEX idx_orders_covering
ON orders (user_id, status, created_at);
```

장점: 테이블 heap 접근 없이 인덱스만으로 응답 → I/O 대폭 감소

---

## Partial Index (PostgreSQL)

```sql
-- 활성 주문만 인덱스 (전체의 5%만 해당)
CREATE INDEX idx_orders_active
ON orders (user_id, created_at)
WHERE status = 'active';

-- 소프트 삭제된 행 제외
CREATE INDEX idx_users_not_deleted
ON users (email)
WHERE deleted_at IS NULL;
```

장점: 인덱스 크기 감소, 쓰기 성능 향상, 특정 쿼리 패턴에 최적

---

## Expression Index

```sql
-- PostgreSQL: 함수 기반 인덱스
CREATE INDEX idx_users_lower_email ON users (LOWER(email));
-- 쿼리: WHERE LOWER(email) = 'user@example.com'

-- JSON 필드 인덱스
CREATE INDEX idx_data_type ON events ((data->>'type'));
-- 쿼리: WHERE data->>'type' = 'click'

-- MySQL: Generated Column + Index
ALTER TABLE users ADD email_lower VARCHAR(255) GENERATED ALWAYS AS (LOWER(email));
CREATE INDEX idx_users_email_lower ON users (email_lower);
```

---

## 인덱스 사용 여부 확인

### PostgreSQL
```sql
-- 인덱스 사용 통계
SELECT indexrelname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan ASC;  -- 사용 안 되는 인덱스 찾기

-- 미사용 인덱스 (idx_scan = 0)
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND schemaname = 'public';
```

### MySQL
```sql
-- 인덱스 사용 통계
SELECT * FROM sys.schema_unused_indexes;
SELECT * FROM sys.schema_redundant_indexes;
```

---

## 인덱스 유지보수

### Bloat 관리 (PostgreSQL)
```sql
-- 인덱스 bloat 확인
SELECT pg_size_pretty(pg_relation_size('idx_orders_user_id')) as index_size;

-- REINDEX (lock 발생)
REINDEX INDEX CONCURRENTLY idx_orders_user_id;  -- PostgreSQL 12+

-- 정기 VACUUM으로 dead tuple 정리
VACUUM (VERBOSE) orders;
```

### Fragmentation (MySQL)
```sql
-- 단편화 확인
SELECT TABLE_NAME, DATA_FREE
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'mydb' AND DATA_FREE > 0;

-- 재구성
ALTER TABLE orders ENGINE=InnoDB;  -- online DDL
OPTIMIZE TABLE orders;
```

---

## Anti-Patterns

| 패턴 | 문제 | 해결 |
|------|------|------|
| 모든 컬럼에 단일 인덱스 | 쓰기 성능 저하, 공간 낭비 | 쿼리 패턴 기반으로 필요한 것만 |
| 중복 인덱스 | (a), (a, b) 있으면 (a)는 불필요 | 중복 제거 |
| 낮은 카디널리티 단독 인덱스 | boolean, status 같은 값 → 풀스캔과 차이 없음 | 복합 인덱스의 일부로 포함 |
| LIKE '%keyword%' | B-tree 인덱스 사용 불가 | GIN trigram 또는 전문검색 |
| 함수 감싼 컬럼 | WHERE YEAR(created_at) = 2026 → 인덱스 무효 | WHERE created_at >= '2026-01-01' AND created_at < '2027-01-01' |
| implicit type cast | WHERE varchar_col = 123 → 인덱스 무효 | 타입 일치시키기 |
