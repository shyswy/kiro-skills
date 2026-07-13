# Kafka Streams & KTable 상세

## 토폴로지 설계

### 기본 구조
```
Source (KStream) → Transform → Filter → Map → Sink (KStream/KTable)
                                    ↓
                              Aggregate → KTable
                                    ↓
                              Join (KStream-KTable)
```

### 토폴로지 예제: 주문 처리
```java
StreamsBuilder builder = new StreamsBuilder();

// 1. 주문 이벤트 스트림
KStream<String, OrderEvent> orders = builder.stream("order.events");

// 2. 사용자 정보 테이블 (compacted topic)
KTable<String, UserProfile> users = builder.table("user.profiles");

// 3. 주문에 사용자 정보 enrichment (KStream-KTable Join)
KStream<String, EnrichedOrder> enriched = orders.join(
    users,
    (order, user) -> new EnrichedOrder(order, user)
);

// 4. 상태별 집계
KTable<String, Long> orderCounts = enriched
    .groupBy((key, value) -> value.getStatus())
    .count(Materialized.as("order-count-store"));

// 5. 결과 출력
enriched.to("order.enriched");
```

---

## Windowing 패턴

### Tumbling Window (고정 크기, 겹침 없음)
```java
// 5분 단위 집계
KTable<Windowed<String>, Long> counts = stream
    .groupByKey()
    .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(5)))
    .count();
```
용도: 5분 단위 요청 수, 시간당 매출

### Hopping Window (고정 크기, 겹침 있음)
```java
// 10분 윈도우, 5분마다 슬라이드
KTable<Windowed<String>, Long> counts = stream
    .groupByKey()
    .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(10))
        .advanceBy(Duration.ofMinutes(5)))
    .count();
```
용도: 이동 평균, 부드러운 추세 분석

### Session Window (활동 기반)
```java
// 30분 비활동 시 세션 종료
KTable<Windowed<String>, Long> sessions = stream
    .groupByKey()
    .windowedBy(SessionWindows.ofInactivityGapWithNoGrace(Duration.ofMinutes(30)))
    .count();
```
용도: 사용자 세션 분석, 활동 패턴

### Sliding Window (정확한 시간 범위)
```java
// 정확히 최근 5분 내 이벤트
KTable<Windowed<String>, Long> counts = stream
    .groupByKey()
    .windowedBy(SlidingWindows.ofTimeDifferenceWithNoGrace(Duration.ofMinutes(5)))
    .count();
```

---

## State Store 관리

### RocksDB (기본 State Store)
```java
// 커스텀 RocksDB 설정
Properties props = new Properties();
props.put(StreamsConfig.ROCKSDB_CONFIG_SETTER_CLASS_CONFIG, CustomRocksDBConfig.class);

public class CustomRocksDBConfig implements RocksDBConfigSetter {
    public void setConfig(String storeName, Options options, Map<String, Object> configs) {
        options.setMaxWriteBufferNumber(4);
        options.setWriteBufferSize(64 * 1024 * 1024);  // 64MB
        BlockBasedTableConfig tableConfig = new BlockBasedTableConfig();
        tableConfig.setBlockCacheSize(128 * 1024 * 1024);  // 128MB cache
        options.setTableFormatConfig(tableConfig);
    }
}
```

### State Store 복구
- Changelog topic에서 자동 복구 (consumer group rebalance 시)
- Standby replicas: `num.standby.replicas=1` (빠른 failover)

### Interactive Queries (외부에서 State Store 조회)
```java
// State Store에 직접 쿼리
ReadOnlyKeyValueStore<String, Long> store =
    streams.store(StoreQueryParameters.fromNameAndType("order-count-store", QueryableStoreTypes.keyValueStore()));

Long count = store.get("active");  // 현재 active 주문 수
```

---

## KTable 패턴

### Compacted Topic → KTable
```java
// user.profiles topic (cleanup.policy=compact)
KTable<String, UserProfile> users = builder.table(
    "user.profiles",
    Consumed.with(Serdes.String(), userProfileSerde),
    Materialized.as("user-store")
);
```

### KTable-KTable Join (Lookup Enrichment)
```java
KTable<String, Product> products = builder.table("products");
KTable<String, Inventory> inventory = builder.table("inventory");

// 상품 + 재고 결합
KTable<String, ProductWithStock> joined = products.join(
    inventory,
    (product, stock) -> new ProductWithStock(product, stock.getQuantity())
);
```

### GlobalKTable (전체 데이터 로컬 복제)
```java
// 모든 인스턴스에 전체 데이터 복제 (작은 참조 데이터용)
GlobalKTable<String, Country> countries = builder.globalTable("countries");

// Foreign Key Join 가능
KStream<String, EnrichedOrder> enriched = orders.join(
    countries,
    (key, order) -> order.getCountryCode(),  // foreign key 추출
    (order, country) -> enrich(order, country)
);
```

---

## 운영 판단 기준

### Partition 증설 시점
- Consumer lag 지속 증가 + Consumer 수 = 현재 파티션 수
- 단일 파티션 처리량 한계 도달 (보통 10MB/s)
- ⚠️ Key 기반 파티셔닝 시 증설하면 기존 key→partition 매핑 깨짐

### Consumer Scale-out 기준
- Lag > 처리 가능량 × 허용 지연 시간
- 예: lag 100만, 처리 1000/s → 1000초 지연. 허용 60초면 17배 scale 필요
- 최대 scale = 파티션 수 (초과 consumer는 idle)

### Streams 인스턴스 수 결정
- 최대 병렬도 = input topic 파티션 수
- 인스턴스 × threads ≤ 파티션 수
- `num.stream.threads`: 인스턴스당 스레드 수 (기본 1)
