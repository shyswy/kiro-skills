# 매핑 설계 상세

## 필드 타입 선택 가이드

| 용도 | 타입 | 예시 |
|------|------|------|
| 정확 매칭, 집계, 정렬 | keyword | status, category, email |
| 전문 검색 | text | description, content |
| 정확 매칭 + 전문 검색 | multi-field (text + keyword) | title, name |
| 숫자 범위/집계 | integer, long, float, double | price, count |
| 날짜 범위/집계 | date | created_at, updated_at |
| true/false | boolean | is_active |
| 배열 내 객체 독립 쿼리 | nested | tags[{name, value}] |
| 배열 내 객체 (독립 쿼리 불필요) | object | metadata |
| IP 주소 | ip | client_ip |
| 지리 좌표 | geo_point | location |
| 대용량 텍스트 (검색 불필요) | text + enabled:false 또는 keyword + ignore_above | raw_log |

---

## Multi-Field 매핑

```json
{
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "analyzer": "nori",
        "fields": {
          "keyword": {
            "type": "keyword",
            "ignore_above": 256
          },
          "ngram": {
            "type": "text",
            "analyzer": "ngram_analyzer"
          }
        }
      }
    }
  }
}
```
- `title`: 전문 검색 (형태소 분석)
- `title.keyword`: 정확 매칭, 정렬, 집계
- `title.ngram`: 부분 문자열 검색

---

## Nested vs Object

### Object (기본)
```json
// 저장
{ "tags": [{"name": "color", "value": "red"}, {"name": "size", "value": "L"}] }

// 내부적으로 flatten됨
{ "tags.name": ["color", "size"], "tags.value": ["red", "L"] }

// 문제: "color=L" 쿼리에도 매칭됨 (cross-object matching)
```

### Nested (독립 객체)
```json
{
  "mappings": {
    "properties": {
      "tags": {
        "type": "nested",
        "properties": {
          "name": { "type": "keyword" },
          "value": { "type": "keyword" }
        }
      }
    }
  }
}

// 쿼리: 정확히 name=color AND value=red인 객체만 매칭
{
  "query": {
    "nested": {
      "path": "tags",
      "query": {
        "bool": {
          "must": [
            { "term": { "tags.name": "color" } },
            { "term": { "tags.value": "red" } }
          ]
        }
      }
    }
  }
}
```

⚠️ Nested 주의: 각 nested 객체가 별도 Lucene 문서 → 메모리/성능 비용 증가

---

## Dynamic Template

```json
{
  "mappings": {
    "dynamic": "strict",  // 미정의 필드 거부 (운영 환경 권장)
    "dynamic_templates": [
      {
        "strings_as_keyword": {
          "match_mapping_type": "string",
          "mapping": {
            "type": "keyword",
            "ignore_above": 512
          }
        }
      },
      {
        "longs_as_integer": {
          "match_mapping_type": "long",
          "mapping": { "type": "integer" }
        }
      },
      {
        "dates": {
          "match": "*_at",
          "mapping": {
            "type": "date",
            "format": "strict_date_optional_time||epoch_millis"
          }
        }
      }
    ]
  }
}
```

---

## Flattened 타입 (동적 키)

```json
// 키가 동적으로 변하는 경우 (labels, metadata)
{
  "mappings": {
    "properties": {
      "labels": {
        "type": "flattened"
      }
    }
  }
}

// 데이터
{ "labels": { "env": "prod", "team": "analytics", "version": "1.2.3" } }

// 쿼리 (term만 가능, range/full-text 불가)
{ "term": { "labels.env": "prod" } }
```

장점: 매핑 폭발 방지 (수천 개 동적 키)
단점: term 쿼리만 가능, 집계 제한적

---

## 매핑 변경 전략

### 변경 불가 항목 (reindex 필요)
- 기존 필드 타입 변경 (text → keyword)
- analyzer 변경
- nested ↔ object 전환

### 변경 가능 항목 (PUT mapping)
- 새 필드 추가
- ignore_above 값 변경
- multi-field 추가
- doc_values 비활성화

### Reindex 없이 우회
```json
// 새 필드로 추가 (기존 유지)
PUT /my-index/_mapping
{
  "properties": {
    "status_v2": { "type": "keyword" }  // 기존 status(text) 유지 + 새 필드 추가
  }
}
// 이후 새 데이터는 status_v2에도 기록, 쿼리는 status_v2 사용
```
