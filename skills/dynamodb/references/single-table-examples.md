# Single-Table Design 실무 예제

## 예제 1: E-Commerce (주문 시스템)

### 접근 패턴
1. 사용자 프로필 조회
2. 사용자의 주문 목록 (최신순)
3. 특정 주문 상세 (주문 항목 포함)
4. 주문 상태별 조회 (전체)
5. 상품별 주문 조회

### 테이블 설계
```
Table: ecommerce

| PK | SK | GSI1PK | GSI1SK | Data |
|----|-----|--------|--------|------|
| USER#u1 | METADATA | EMAIL#user@test.com | USER#u1 | {name, email, address} |
| USER#u1 | ORDER#2026-05-20#o1 | STATUS#shipped | ORDER#2026-05-20 | {total, status} |
| USER#u1 | ORDER#2026-05-21#o2 | STATUS#pending | ORDER#2026-05-21 | {total, status} |
| ORDER#o1 | ITEM#i1 | PRODUCT#p1 | ORDER#o1 | {qty, price, productName} |
| ORDER#o1 | ITEM#i2 | PRODUCT#p2 | ORDER#o1 | {qty, price, productName} |
| ORDER#o1 | METADATA | — | — | {userId, shippingAddress, createdAt} |
```

### 쿼리 매핑
```
1. 사용자 프로필: Query PK=USER#u1, SK=METADATA
2. 사용자 주문 목록: Query PK=USER#u1, SK begins_with "ORDER#", ScanIndexForward=false
3. 주문 상세 + 항목: Query PK=ORDER#o1 (METADATA + ITEM# 모두 반환)
4. 상태별 주문: Query GSI1 PK=STATUS#pending
5. 상품별 주문: Query GSI1 PK=PRODUCT#p1
```

---

## 예제 2: SaaS Multi-Tenant

### 접근 패턴
1. 테넌트 정보 조회
2. 테넌트의 사용자 목록
3. 사용자 이메일로 조회 (로그인)
4. 테넌트의 프로젝트 목록
5. 프로젝트의 태스크 목록

### 테이블 설계
```
Table: saas

| PK | SK | GSI1PK | GSI1SK |
|----|-----|--------|--------|
| TENANT#t1 | METADATA | — | — |
| TENANT#t1 | USER#u1 | EMAIL#admin@company.com | TENANT#t1 |
| TENANT#t1 | USER#u2 | EMAIL#dev@company.com | TENANT#t1 |
| TENANT#t1 | PROJECT#p1 | TENANT#t1#PROJECT | CREATED#2026-05-01 |
| PROJECT#p1 | TASK#tk1 | STATUS#todo | PRIORITY#1 |
| PROJECT#p1 | TASK#tk2 | STATUS#done | PRIORITY#2 |
```

### 테넌트 격리
- PK에 TENANT# prefix → 다른 테넌트 데이터 접근 불가
- IAM 조건으로 추가 보안: `dynamodb:LeadingKeys` 조건

---

## 예제 3: 소셜 미디어 (팔로우/피드)

### 접근 패턴
1. 사용자 프로필
2. 사용자의 팔로잉 목록
3. 사용자의 팔로워 목록
4. 사용자의 포스트 목록 (최신순)
5. 피드 (팔로잉한 사람들의 포스트)

### 테이블 설계
```
Table: social

| PK | SK | GSI1PK | GSI1SK |
|----|-----|--------|--------|
| USER#u1 | METADATA | — | — |
| USER#u1 | FOLLOWING#u2 | USER#u2 | FOLLOWER#u1 |
| USER#u1 | FOLLOWING#u3 | USER#u3 | FOLLOWER#u1 |
| USER#u1 | POST#2026-05-20T10:00#p1 | — | — |
| USER#u1 | POST#2026-05-21T09:00#p2 | — | — |
```

### 쿼리 매핑
```
1. 프로필: PK=USER#u1, SK=METADATA
2. 팔로잉: PK=USER#u1, SK begins_with "FOLLOWING#"
3. 팔로워: GSI1 PK=USER#u1, SK begins_with "FOLLOWER#"
4. 내 포스트: PK=USER#u1, SK begins_with "POST#", ScanIndexForward=false
5. 피드: Fan-out on write (별도 FEED 항목) 또는 Fan-out on read (팔로잉 각각 조회)
```

---

## 예제 4: IoT 디바이스 관리

### 접근 패턴
1. 디바이스 정보 조회
2. 디바이스 그룹별 목록
3. 디바이스 최근 텔레메트리
4. 특정 기간 텔레메트리 조회
5. 오프라인 디바이스 목록

### 테이블 설계
```
Table: iot

| PK | SK | GSI1PK | GSI1SK |
|----|-----|--------|--------|
| DEVICE#d1 | METADATA | GROUP#floor-1 | STATUS#online |
| DEVICE#d1 | TELEMETRY#2026-05-20T14:00 | — | — |
| DEVICE#d1 | TELEMETRY#2026-05-20T14:05 | — | — |
| DEVICE#d2 | METADATA | GROUP#floor-2 | STATUS#offline |
```

### 쿼리 매핑
```
1. 디바이스 정보: PK=DEVICE#d1, SK=METADATA
2. 그룹별: GSI1 PK=GROUP#floor-1
3. 최근 텔레메트리: PK=DEVICE#d1, SK begins_with "TELEMETRY#", ScanIndexForward=false, Limit=10
4. 기간 조회: PK=DEVICE#d1, SK between "TELEMETRY#2026-05-20T14:00" and "TELEMETRY#2026-05-20T15:00"
5. 오프라인: GSI1 SK begins_with "STATUS#offline" (Sparse Index 활용)
```

---

## Single-Table 설계 체크리스트

- [ ] 모든 접근 패턴을 먼저 나열했는가?
- [ ] PK로 가장 빈번한 조회의 파티션을 결정했는가?
- [ ] SK로 1:N 관계와 정렬을 표현했는가?
- [ ] GSI는 최소한으로 (최대 5개 권장)?
- [ ] 핫 파티션 위험이 없는가? (특정 PK에 트래픽 집중)
- [ ] TTL 대상 항목이 있는가? (오래된 텔레메트리, 세션 등)
- [ ] 항목 크기가 400KB 이하인가?
- [ ] 트랜잭션이 필요한 패턴은 같은 파티션에 있는가?

---

## Single-Table vs Multi-Table 판단

| 기준 | Single-Table | Multi-Table |
|------|:---:|:---:|
| 팀 규모 | 소규모 (1~3명) | 대규모 (여러 팀) |
| 접근 패턴 | 명확하고 안정적 | 자주 변경됨 |
| 엔티티 간 관계 | 밀접 (같이 조회) | 독립적 |
| 트랜잭션 | 엔티티 간 필요 | 엔티티별 독립 |
| 운영 복잡도 | 높음 (스키마 이해 필요) | 낮음 (직관적) |
