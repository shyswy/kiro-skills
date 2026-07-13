# DynamoDB 접근 패턴 설계

## 접근 패턴 먼저, 키 설계 나중

DynamoDB 설계 순서:
1. 모든 접근 패턴(쿼리) 나열
2. 각 패턴에 필요한 PK/SK 결정
3. GSI 필요 여부 판단
4. 테이블 스키마 확정

---

## 1:N 관계

### 사용자 → 주문 (User has many Orders)
```
PK: USER#userId
SK: ORDER#orderId

접근 패턴:
- 사용자 정보 조회: PK=USER#123, SK=METADATA
- 사용자의 주문 목록: PK=USER#123, SK begins_with "ORDER#"
- 특정 주문 조회: PK=USER#123, SK=ORDER#456
- 최근 주문 N개: PK=USER#123, SK begins_with "ORDER#", ScanIndexForward=false, Limit=N
```

### 데이터 예시
| PK | SK | Attributes |
|----|-----|-----------|
| USER#123 | METADATA | {name, email, createdAt} |
| USER#123 | ORDER#2026-05-20#001 | {total, status, items} |
| USER#123 | ORDER#2026-05-21#002 | {total, status, items} |

> SK에 날짜를 포함하면 시간순 정렬 자동 보장

---

## M:N 관계

### 사용자 ↔ 그룹 (User belongs to many Groups, Group has many Users)

#### 방법 1: 양방향 항목
```
# 사용자 → 그룹 조회
PK: USER#userId, SK: GROUP#groupId

# 그룹 → 사용자 조회 (GSI 역전)
GSI1PK: GROUP#groupId, GSI1SK: USER#userId
```

| PK | SK | GSI1PK | GSI1SK |
|----|-----|--------|--------|
| USER#123 | GROUP#A | GROUP#A | USER#123 |
| USER#123 | GROUP#B | GROUP#B | USER#123 |
| USER#456 | GROUP#A | GROUP#A | USER#456 |

#### 방법 2: Adjacency List (복잡한 관계)
```
PK: ENTITY#id
SK: RELATION#targetId

접근 패턴:
- 엔티티 정보: PK=ENTITY#123, SK=METADATA
- 엔티티의 관계: PK=ENTITY#123, SK begins_with "RELATION#"
- 역방향 조회: GSI (SK → PK 역전)
```

---

## 계층 구조 (Tree)

### 조직도 / 카테고리 트리
```
PK: ORG#orgId
SK: 경로 기반 (ancestors)

예시:
PK=ORG#1, SK=ROOT                          → 최상위
PK=ORG#1, SK=ROOT#DEPT-A                   → 부서 A
PK=ORG#1, SK=ROOT#DEPT-A#TEAM-1           → 팀 1
PK=ORG#1, SK=ROOT#DEPT-A#TEAM-1#USER-123  → 사용자
```

접근 패턴:
- 특정 노드의 모든 하위: `SK begins_with "ROOT#DEPT-A#"`
- 특정 레벨만: `SK begins_with "ROOT#DEPT-A#TEAM-"` (구분자 활용)
- 직속 자식만: filter로 depth 제한

---

## 시계열 데이터

### IoT 센서 데이터
```
PK: DEVICE#deviceId#2026-05-20  (일별 파티션)
SK: 14:30:00#metric-name

접근 패턴:
- 특정 디바이스의 오늘 데이터: PK=DEVICE#dev1#2026-05-20
- 특정 시간 범위: SK between "14:00:00" and "15:00:00"
```

> PK에 날짜를 포함하여 핫 파티션 방지 + 오래된 데이터 TTL 삭제 용이

### 고빈도 쓰기 (Write Sharding)
```
# 초당 수천 건 쓰기 시 파티션 분산
PK: METRIC#cpu#SHARD-{0-9}  (10개 shard)
SK: 2026-05-20T14:30:00

# 읽기 시 모든 shard 병렬 조회 후 합산
```

---

## 이벤트 소싱

### 이벤트 저장
```
PK: AGGREGATE#orderId
SK: EVENT#00001  (sequence number)

| PK | SK | eventType | payload | timestamp |
|----|-----|-----------|---------|-----------|
| AGGREGATE#order-1 | EVENT#00001 | OrderCreated | {...} | 2026-05-20T10:00 |
| AGGREGATE#order-1 | EVENT#00002 | ItemAdded | {...} | 2026-05-20T10:01 |
| AGGREGATE#order-1 | EVENT#00003 | PaymentCompleted | {...} | 2026-05-20T10:05 |
```

접근 패턴:
- 전체 이벤트 히스토리: PK=AGGREGATE#order-1, SK begins_with "EVENT#"
- 특정 시점 이후: PK=AGGREGATE#order-1, SK > "EVENT#00002"
- 최신 상태 복원: 모든 이벤트 순서대로 replay

---

## 필터링 패턴

### Sparse Index (GSI)
```
# "featured" 상품만 GSI에 포함 (속성이 있는 항목만)
GSI: featuredAt (존재하는 항목만 인덱싱)

# 전체 상품 중 featured만 빠르게 조회
Query GSI where featuredAt exists
```

### Composite Sort Key (복합 필터)
```
SK: STATUS#active#CATEGORY#electronics#PRICE#050000

접근 패턴:
- 활성 상품: SK begins_with "STATUS#active"
- 활성 + 전자제품: SK begins_with "STATUS#active#CATEGORY#electronics"
- 가격 범위: SK between "STATUS#active#CATEGORY#electronics#PRICE#010000"
                    and "STATUS#active#CATEGORY#electronics#PRICE#100000"
```

> 가격은 zero-padding으로 문자열 정렬 = 숫자 정렬 보장

---

## GSI 오버로딩

### 하나의 GSI로 여러 접근 패턴 지원
```
GSI1PK / GSI1SK를 엔티티 타입에 따라 다르게 사용:

| Entity | GSI1PK | GSI1SK | 용도 |
|--------|--------|--------|------|
| User | EMAIL#user@test.com | USER#123 | 이메일로 사용자 조회 |
| Order | STATUS#pending | ORDER#2026-05-20 | 상태별 주문 조회 |
| Product | CATEGORY#electronics | PRICE#050000 | 카테고리+가격 조회 |
```

하나의 GSI로 3가지 다른 접근 패턴을 지원.
