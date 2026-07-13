# 쿼리 최적화 상세

## Bool Query 조합 패턴

### 기본 구조
```json
{
  "query": {
    "bool": {
      "must": [],      // AND + 스코어링 (검색 관련도)
      "filter": [],    // AND + 캐시 (필터링만, 스코어 무시)
      "should": [],    // OR (minimum_should_match로 제어)
      "must_not": []   // NOT + 캐시
    }
  }
}
```

### 성능 규칙
- **filter > must**: 스코어링 불필요한 조건은 반드시 filter로
- **filter는 캐시됨**: 동일 조건 반복 시 즉시 응답
- **must_not도 캐시됨**: 제외 조건에 활용

### 실무 예제: 상품 검색
```json
{
  "query": {
    "bool": {
      "must": [
        { "match": { "title": "무선 이어폰" } }  // 검색어 (스코어링)
      ],
      "filter": [
        { "term": { "status": "active" } },       // 필터 (캐시)
        { "range": { "price": { "gte": 10000, "lte": 100000 } } },
        { "terms": { "category": ["electronics", "audio"] } }
      ],
      "should": [
        { "term": { "brand": "samsung" } },       // 보너스 스코어
        { "range": { "rating": { "gte": 4.5 } } }
      ],
      "must_not": [
        { "term": { "is_deleted": true } }
      ]
    }
  }
}
```

---

## 스코어링 튜닝

### Function Score
```json
{
  "query": {
    "function_score": {
      "query": { "match": { "title": "이어폰" } },
      "functions": [
        {
          "filter": { "term": { "is_promoted": true } },
          "weight": 2
        },
        {
          "gauss": {
            "created_at": {
              "origin": "now",
              "scale": "7d",
              "decay": 0.5
            }
          }
        },
        {
          "field_value_factor": {
            "field": "popularity",
            "modifier": "log1p",
            "factor": 0.5
          }
        }
      ],
      "score_mode": "sum",
      "boost_mode": "multiply"
    }
  }
}
```

### Boosting
```json
{
  "query": {
    "boosting": {
      "positive": { "match": { "title": "이어폰" } },
      "negative": { "term": { "condition": "refurbished" } },
      "negative_boost": 0.5  // 리퍼 상품 스코어 50% 감소
    }
  }
}
```

---

## Aggregation 최적화

### 집계 성능 팁
- `size: 0` — 검색 결과 불필요 시 (집계만 필요)
- `shard_size` — 정확도 vs 성능 (기본: size × 1.5 + 10)
- `execution_hint: map` — 카디널리티 낮은 필드에 유리
- `collect_mode: breadth_first` — 깊은 중첩 집계 시

### 자주 쓰는 집계 패턴
```json
// 카테고리별 평균 가격 + 상위 5개
{
  "size": 0,
  "aggs": {
    "by_category": {
      "terms": { "field": "category", "size": 5 },
      "aggs": {
        "avg_price": { "avg": { "field": "price" } },
        "price_ranges": {
          "range": {
            "field": "price",
            "ranges": [
              { "to": 10000 },
              { "from": 10000, "to": 50000 },
              { "from": 50000 }
            ]
          }
        }
      }
    }
  }
}
```

### Date Histogram + 이동 평균
```json
{
  "size": 0,
  "aggs": {
    "daily": {
      "date_histogram": {
        "field": "created_at",
        "calendar_interval": "day"
      },
      "aggs": {
        "total_sales": { "sum": { "field": "amount" } },
        "moving_avg": {
          "moving_avg": {
            "buckets_path": "total_sales",
            "window": 7
          }
        }
      }
    }
  }
}
```

---

## 페이지네이션 전략

| 방법 | 용도 | 한계 |
|------|------|------|
| from + size | 일반 페이지 (< 10000건) | 10000건 초과 불가 (기본) |
| search_after | Deep pagination | 이전 페이지 이동 불가 |
| scroll | 대량 export | 실시간 변경 반영 안 됨 |
| PIT + search_after | 실시간 deep pagination | 가장 권장 (7.10+) |

### search_after 예제
```json
// 첫 페이지
{ "size": 20, "sort": [{ "created_at": "desc" }, { "_id": "asc" }] }

// 다음 페이지 (이전 결과의 마지막 sort 값 사용)
{
  "size": 20,
  "sort": [{ "created_at": "desc" }, { "_id": "asc" }],
  "search_after": ["2026-05-20T10:00:00.000Z", "doc-id-123"]
}
```

---

## 검색 성능 체크리스트

- [ ] 불필요한 필드 `_source` 제외 또는 `stored_fields` 사용
- [ ] filter context 최대 활용 (캐시)
- [ ] 와일드카드 쿼리 최소화 (`*keyword*` 대신 ngram)
- [ ] nested 쿼리 최소화 (가능하면 flattened 또는 denormalize)
- [ ] 집계 시 `size: 0` (결과 문서 불필요 시)
- [ ] 인덱스 정렬 활용 (`index.sort.field` 설정)
- [ ] `preference=_local` (같은 노드 shard 우선)
- [ ] 캐시 워밍: 자주 쓰는 쿼리 미리 실행
