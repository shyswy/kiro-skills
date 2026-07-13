# SQL 쿼리 튜닝 가이드

## 실행계획 읽기

### PostgreSQL EXPLAIN 출력 해석
```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM orders WHERE user_id = 123 AND status = 'active';
```

주요 지표:
- `actual time`: 첫 행 반환 시간 .. 전체 완료 시간 (ms)
- `rows`: 예상 vs 실제 행 수 (차이 크면 통계 갱신 필요)
- `Buffers: shared hit/read`: 캐시 히트 vs 디스크 읽기
- `loops`: 반복 실행 횟수 (Nested Loop 시 주의)

### 위험 신호
| 패턴 | 의미 | 대응 |
|------|------|------|
| Seq Scan (대용량) | 풀 테이블 스캔 | 인덱스 추가 또는 쿼리 조건 변경 |
| Nested Loop (큰 outer) | O(N×M) 조인 | Hash Join 유도 또는 인덱스 추가 |
| Sort (external) | 메모리 초과 정렬 | work_mem 증가 또는 인덱스 정렬 활용 |
| Hash (batches > 1) | 해시 테이블 디스크 스필 | work_mem 증가 |
| Bitmap Heap Scan (lossy) | 비트맵 메모리 초과 | effective_cache_size 조정 |

### MySQL EXPLAIN 핵심 컬럼
- `type`: ALL(풀스캔) < index < range < ref < eq_ref < const
- `key`: 실제 사용된 인덱스
- `rows`: 예상 스캔 행 수
- `Extra`: Using filesort, Using temporary → 개선 필요

---

## 쿼리 리팩토링 패턴

### 1. 서브쿼리 → JOIN 변환
```sql
-- Bad: 상관 서브쿼리 (행마다 실행)
SELECT * FROM orders o
WHERE o.total > (SELECT AVG(total) FROM orders WHERE user_id = o.user_id);

-- Good: JOIN + 윈도우 함수
SELECT o.*
FROM orders o
JOIN (
  SELECT user_id, AVG(total) as avg_total
  FROM orders GROUP BY user_id
) a ON o.user_id = a.user_id
WHERE o.total > a.avg_total;
```

### 2. OR → UNION ALL
```sql
-- Bad: OR은 인덱스 활용 어려움
SELECT * FROM users WHERE email = 'a@b.com' OR phone = '010-1234';

-- Good: 각각 인덱스 활용
SELECT * FROM users WHERE email = 'a@b.com'
UNION ALL
SELECT * FROM users WHERE phone = '010-1234' AND email != 'a@b.com';
```

### 3. EXISTS vs IN
```sql
-- 서브쿼리 결과가 큰 경우: EXISTS가 유리
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 서브쿼리 결과가 작은 경우: IN이 유리
SELECT * FROM orders WHERE user_id IN (SELECT id FROM users WHERE vip = true);
```

### 4. OFFSET 페이지네이션 → Keyset 페이지네이션
```sql
-- Bad: OFFSET이 커질수록 느려짐
SELECT * FROM posts ORDER BY created_at DESC LIMIT 20 OFFSET 10000;

-- Good: 마지막 본 값 기준
SELECT * FROM posts
WHERE created_at < '2026-05-20T10:00:00'
ORDER BY created_at DESC LIMIT 20;
```

### 5. COUNT 최적화
```sql
-- Bad: 정확한 카운트 (대용량 테이블에서 느림)
SELECT COUNT(*) FROM logs WHERE created_at > '2026-01-01';

-- Good: 근사치로 충분한 경우 (PostgreSQL)
SELECT reltuples::bigint FROM pg_class WHERE relname = 'logs';

-- Good: 존재 여부만 확인
SELECT EXISTS(SELECT 1 FROM logs WHERE created_at > '2026-01-01');
```

### 6. 배치 처리
```sql
-- Bad: 한 번에 대량 UPDATE (lock 오래 유지)
UPDATE orders SET status = 'archived' WHERE created_at < '2025-01-01';

-- Good: 배치 단위로 분할
UPDATE orders SET status = 'archived'
WHERE id IN (
  SELECT id FROM orders WHERE created_at < '2025-01-01' AND status != 'archived'
  LIMIT 1000
);
-- 반복 실행 (affected rows = 0 될 때까지)
```

---

## 통계 관리

### PostgreSQL
```sql
-- 테이블 통계 갱신
ANALYZE orders;

-- 특정 컬럼 통계 상세도 증가 (기본 100, 최대 10000)
ALTER TABLE orders ALTER COLUMN status SET STATISTICS 500;
ANALYZE orders;

-- 통계 확인
SELECT * FROM pg_stats WHERE tablename = 'orders' AND attname = 'status';
```

### MySQL
```sql
-- 통계 갱신
ANALYZE TABLE orders;

-- InnoDB 통계 설정
SET GLOBAL innodb_stats_persistent_sample_pages = 200;
```

---

## 힌트 사용 (최후의 수단)

### PostgreSQL (pg_hint_plan 확장)
```sql
/*+ SeqScan(orders) */ -- 강제 풀스캔
/*+ IndexScan(orders idx_orders_user_id) */ -- 특정 인덱스 강제
/*+ HashJoin(orders users) */ -- 조인 방식 강제
/*+ Set(work_mem '256MB') */ -- 세션 파라미터 변경
```

### MySQL
```sql
SELECT /*+ INDEX(orders idx_user_status) */ * FROM orders WHERE ...;
SELECT /*+ NO_INDEX(orders idx_created_at) */ * FROM orders WHERE ...;
SELECT /*+ JOIN_ORDER(users, orders) */ * FROM users JOIN orders ON ...;
```

> ⚠️ 힌트는 옵티마이저보다 사람이 더 잘 아는 경우에만 사용. 데이터 분포 변경 시 힌트가 오히려 성능 저하 유발.

---

## 판단 기준: 인덱스 vs 쿼리 리팩토링 vs 아키텍처 변경

| 상황 | 접근 |
|------|------|
| 단순 WHERE 조건 느림 | 인덱스 추가 |
| 인덱스 있는데도 느림 | 쿼리 리팩토링 (실행계획 확인) |
| 조인 테이블 5개 이상 | 비정규화 또는 materialized view 검토 |
| 집계 쿼리 느림 | 사전 집계 테이블 또는 CQRS |
| 단일 쿼리로 해결 불가 | 캐시 레이어 (Redis) 또는 검색엔진 (ES) 분리 |
