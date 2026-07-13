# 인덱스 운영 가이드

## Reindex 절차 (Zero-Downtime)

### 전체 흐름
```
1. 새 인덱스 생성 (new mapping)
2. Alias를 활용한 이중 쓰기 설정
3. Reindex API로 기존 데이터 복사
4. Alias 스왑 (atomic)
5. 구 인덱스 삭제
```

### Step-by-Step

```json
// 1. 새 인덱스 생성
PUT /products-v2
{
  "settings": { "number_of_shards": 3, "number_of_replicas": 1 },
  "mappings": { /* 새 매핑 */ }
}

// 2. Reindex (비동기, 대용량)
POST /_reindex?wait_for_completion=false
{
  "source": { "index": "products-v1", "size": 5000 },
  "dest": { "index": "products-v2" }
}
// → task_id 반환

// 3. 진행 상황 확인
GET /_tasks/{task_id}

// 4. Alias 스왑 (atomic operation)
POST /_aliases
{
  "actions": [
    { "remove": { "index": "products-v1", "alias": "products" } },
    { "add": { "index": "products-v2", "alias": "products" } }
  ]
}

// 5. 구 인덱스 삭제
DELETE /products-v1
```

### 병렬 Reindex (대용량)
```json
POST /_reindex?wait_for_completion=false
{
  "source": { "index": "logs-2025", "size": 10000, "slice": { "id": 0, "max": 5 } },
  "dest": { "index": "logs-2025-v2" }
}
// slice 0~4까지 5개 병렬 실행
// 또는 slices=auto (자동 분할)
POST /_reindex?slices=auto&wait_for_completion=false
{
  "source": { "index": "logs-2025" },
  "dest": { "index": "logs-2025-v2" }
}
```

### 변환하면서 Reindex
```json
POST /_reindex
{
  "source": { "index": "products-v1" },
  "dest": { "index": "products-v2" },
  "script": {
    "source": "ctx._source.status = ctx._source.remove('is_active') ? 'active' : 'inactive'"
  }
}
```

---

## Alias 관리

### 읽기/쓰기 분리
```json
POST /_aliases
{
  "actions": [
    { "add": { "index": "products-v2", "alias": "products-read" } },
    { "add": { "index": "products-v2", "alias": "products-write", "is_write_index": true } }
  ]
}
```

### Filter Alias (뷰)
```json
POST /_aliases
{
  "actions": [
    {
      "add": {
        "index": "orders",
        "alias": "orders-active",
        "filter": { "term": { "status": "active" } }
      }
    }
  ]
}
// orders-active로 검색하면 status=active만 반환
```

### Routing Alias (성능)
```json
POST /_aliases
{
  "actions": [
    {
      "add": {
        "index": "orders",
        "alias": "orders-user-123",
        "filter": { "term": { "user_id": "123" } },
        "routing": "123"  // 특정 shard만 검색
      }
    }
  ]
}
```

---

## Rollover 설정

### Data Stream (권장, 7.9+)
```json
// Index Template
PUT /_index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "data_stream": {},
  "template": {
    "settings": {
      "number_of_shards": 2,
      "number_of_replicas": 1
    },
    "mappings": { /* ... */ }
  }
}

// Data Stream 생성 (첫 문서 인덱싱 시 자동)
POST /logs-myapp/_doc
{ "message": "hello", "@timestamp": "2026-05-20T10:00:00Z" }
```

### ILM Policy
```json
PUT /_ilm/policy/logs-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_size": "50gb",
            "max_age": "1d",
            "max_docs": 100000000
          },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 },
          "set_priority": { "priority": 50 }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "set_priority": { "priority": 0 }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": { "delete": {} }
      }
    }
  }
}
```

---

## 인덱스 최적화

### Force Merge (읽기 전용 인덱스)
```json
// Warm/Cold 인덱스에서 세그먼트 병합 → 검색 성능 향상
POST /logs-2025-01/_forcemerge?max_num_segments=1

// ⚠️ 쓰기 중인 인덱스에서는 절대 실행 금지
```

### Shrink (shard 수 줄이기)
```json
// 1. 인덱스를 단일 노드로 이동
PUT /logs-2025-01/_settings
{
  "index.routing.allocation.require._name": "node-1",
  "index.blocks.write": true
}

// 2. Shrink 실행
POST /logs-2025-01/_shrink/logs-2025-01-shrunk
{
  "settings": { "index.number_of_shards": 1 }
}
```

### 설정 튜닝
```json
// 벌크 인덱싱 시 (임시)
PUT /my-index/_settings
{
  "index.refresh_interval": "30s",     // 기본 1s → 30s (쓰기 성능 향상)
  "index.number_of_replicas": 0,       // 벌크 중 replica 비활성화
  "index.translog.durability": "async"  // 비동기 translog (위험하지만 빠름)
}

// 벌크 완료 후 복원
PUT /my-index/_settings
{
  "index.refresh_interval": "1s",
  "index.number_of_replicas": 1,
  "index.translog.durability": "request"
}
```

---

## 장애 대응

### Red Cluster 복구
1. `GET /_cluster/health` → unassigned shards 확인
2. `GET /_cluster/allocation/explain` → 할당 실패 원인
3. 원인별 대응:
   - 디스크 부족: 오래된 인덱스 삭제 또는 노드 추가
   - 노드 다운: 노드 복구 또는 replica 재할당
   - shard 손상: `POST /_cluster/reroute` (allocate_stale_primary)

### Shard 재할당
```json
POST /_cluster/reroute
{
  "commands": [
    {
      "allocate_replica": {
        "index": "my-index",
        "shard": 0,
        "node": "node-2"
      }
    }
  ]
}
```
