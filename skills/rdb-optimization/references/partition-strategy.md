# 파티셔닝 전략

## 파티셔닝 판단 기준

| 조건 | 파티셔닝 적합 |
|------|:---:|
| 테이블 크기 > 100GB | ✅ |
| 시계열 데이터 (로그, 이벤트, 메트릭) | ✅ |
| 오래된 데이터 주기적 삭제 필요 | ✅ |
| 쿼리가 항상 특정 범위/카테고리 조건 포함 | ✅ |
| 랜덤 접근 패턴 (PK lookup 위주) | ❌ |
| 테이블 크기 < 10GB | ❌ |

---

## PostgreSQL 파티셔닝

### Range Partition (시계열)
```sql
CREATE TABLE events (
    id bigint GENERATED ALWAYS AS IDENTITY,
    event_type text NOT NULL,
    payload jsonb,
    created_at timestamptz NOT NULL
) PARTITION BY RANGE (created_at);

-- 월별 파티션 생성
CREATE TABLE events_2026_01 PARTITION OF events
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE events_2026_02 PARTITION OF events
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

-- 기본 파티션 (범위 밖 데이터 수용)
CREATE TABLE events_default PARTITION OF events DEFAULT;
```

### List Partition (카테고리)
```sql
CREATE TABLE orders (
    id bigint,
    region text NOT NULL,
    total numeric
) PARTITION BY LIST (region);

CREATE TABLE orders_kr PARTITION OF orders FOR VALUES IN ('KR');
CREATE TABLE orders_us PARTITION OF orders FOR VALUES IN ('US');
CREATE TABLE orders_eu PARTITION OF orders FOR VALUES IN ('EU', 'UK');
```

### Hash Partition (균등 분산)
```sql
CREATE TABLE sessions (
    id uuid PRIMARY KEY,
    user_id bigint,
    data jsonb
) PARTITION BY HASH (id);

CREATE TABLE sessions_0 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE sessions_1 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE sessions_2 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE sessions_3 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 3);
```

---

## MySQL 파티셔닝

### Range Columns
```sql
CREATE TABLE events (
    id BIGINT AUTO_INCREMENT,
    event_type VARCHAR(50),
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE COLUMNS (created_at) (
    PARTITION p2026_01 VALUES LESS THAN ('2026-02-01'),
    PARTITION p2026_02 VALUES LESS THAN ('2026-03-01'),
    PARTITION p_future VALUES LESS THAN (MAXVALUE)
);
```

> ⚠️ MySQL 파티셔닝 제약: PK에 파티션 키 포함 필수, FK 사용 불가

---

## 파티션 관리 자동화

### PostgreSQL: pg_partman 확장
```sql
-- 자동 파티션 생성/삭제
SELECT partman.create_parent(
    p_parent_table := 'public.events',
    p_control := 'created_at',
    p_type := 'native',
    p_interval := '1 month',
    p_premake := 3  -- 3개월 미리 생성
);

-- 오래된 파티션 자동 삭제 (retention)
UPDATE partman.part_config
SET retention = '12 months', retention_keep_table = false
WHERE parent_table = 'public.events';
```

### MySQL: 수동 스크립트
```sql
-- 새 파티션 추가
ALTER TABLE events REORGANIZE PARTITION p_future INTO (
    PARTITION p2026_03 VALUES LESS THAN ('2026-04-01'),
    PARTITION p_future VALUES LESS THAN (MAXVALUE)
);

-- 오래된 파티션 삭제 (즉시, lock 최소)
ALTER TABLE events DROP PARTITION p2025_01;
```

---

## 파티션 쿼리 최적화 (Partition Pruning)

```sql
-- Good: 파티션 키 조건 포함 → 해당 파티션만 스캔
SELECT * FROM events
WHERE created_at >= '2026-05-01' AND created_at < '2026-06-01';

-- Bad: 파티션 키 없음 → 모든 파티션 스캔
SELECT * FROM events WHERE event_type = 'click';

-- 확인: EXPLAIN에서 파티션 pruning 확인
EXPLAIN SELECT * FROM events WHERE created_at >= '2026-05-01';
-- → "Partitions: events_2026_05" (pruning 성공)
```

---

## 기존 테이블 → 파티션 마이그레이션

### 방법 1: 새 테이블 생성 + 데이터 이동
```sql
-- 1. 파티션 테이블 생성
CREATE TABLE events_new (...) PARTITION BY RANGE (created_at);
-- 파티션들 생성...

-- 2. 데이터 복사 (배치)
INSERT INTO events_new SELECT * FROM events WHERE created_at >= '2026-01-01' AND created_at < '2026-02-01';
-- 월별 반복...

-- 3. 전환 (짧은 lock)
BEGIN;
ALTER TABLE events RENAME TO events_old;
ALTER TABLE events_new RENAME TO events;
COMMIT;

-- 4. 검증 후 old 삭제
DROP TABLE events_old;
```

### 방법 2: pg_partman + ATTACH (PostgreSQL)
```sql
-- 기존 테이블을 파티션으로 attach
ALTER TABLE events_new ATTACH PARTITION events_2026_05
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
```

---

## 주의사항

- 파티션 키는 변경 불가 (UPDATE 시 행 이동 발생 → PostgreSQL 11+에서 지원하지만 비용 큼)
- 파티션 수 과다 주의: 1000개 이상이면 planning 시간 증가
- 인덱스는 각 파티션에 개별 생성됨 (글로벌 인덱스 없음 — PostgreSQL)
- UNIQUE constraint는 파티션 키를 포함해야 함
