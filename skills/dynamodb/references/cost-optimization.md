# DynamoDB 비용 최적화

## 용량 모드 선택 기준

| 기준 | On-Demand | Provisioned |
|------|:---------:|:-----------:|
| 트래픽 패턴 | 예측 불가, 스파이크 | 안정적, 예측 가능 |
| 신규 서비스 | ✅ (패턴 파악 전) | ❌ |
| 비용 | 요청당 과금 (비쌈) | 시간당 과금 (저렴) |
| 스케일링 | 즉시 (제한 있음) | Auto Scaling (지연) |
| 비용 예측 | 어려움 | 쉬움 |

### 전환 시점
```
On-Demand → Provisioned:
- 트래픽 패턴이 안정화된 후 (보통 2~4주 관찰)
- 월 비용이 Provisioned + Auto Scaling보다 30%+ 비쌀 때

Provisioned → On-Demand:
- 트래픽 스파이크가 빈번하고 예측 불가
- Throttling이 자주 발생
- Auto Scaling 반응 속도가 부족할 때
```

---

## WCU/RCU 계산

### 기본 공식
```
1 WCU = 1KB 쓰기/초
1 RCU = 4KB 강력한 일관성 읽기/초 (또는 8KB 최종 일관성)

예시: 평균 항목 크기 2KB, 초당 100건 쓰기
→ 필요 WCU = ceil(2/1) × 100 = 200 WCU

예시: 평균 항목 크기 8KB, 초당 500건 읽기 (최종 일관성)
→ 필요 RCU = ceil(8/4) × 500 / 2 = 500 RCU
```

### 트랜잭션 비용
```
TransactWriteItems: 일반 쓰기의 2배 WCU
TransactGetItems: 일반 읽기의 2배 RCU

예시: 2KB 항목 트랜잭션 쓰기
→ ceil(2/1) × 2 = 4 WCU per item
```

---

## Auto Scaling 설정

```json
// CloudFormation/CDK 예시
{
  "TableName": "my-table",
  "BillingMode": "PROVISIONED",
  "ProvisionedThroughput": {
    "ReadCapacityUnits": 100,
    "WriteCapacityUnits": 50
  }
}

// Auto Scaling 정책
{
  "TargetTrackingScalingPolicyConfiguration": {
    "TargetValue": 70.0,           // 목표 사용률 70%
    "ScaleInCooldown": 60,         // 축소 대기 (초)
    "ScaleOutCooldown": 0          // 확장 즉시
  },
  "MinCapacity": 50,
  "MaxCapacity": 1000
}
```

### Auto Scaling 주의사항
- Scale-out 반응 시간: 1~2분 (스파이크에 취약)
- Scale-in은 보수적 (과금 방지)
- 예측 가능한 스파이크: Scheduled Scaling 병행

---

## Reserved Capacity

### 계산 예시
```
On-Demand 비용 (ap-northeast-2):
- 쓰기: $1.4846 / 백만 WRU
- 읽기: $0.297 / 백만 RRU

Provisioned 비용:
- WCU: $0.000742 / 시간 (= $0.534 / 월)
- RCU: $0.000148 / 시간 (= $0.107 / 월)

Reserved (1년):
- WCU: ~$0.000495 / 시간 (33% 할인)
- RCU: ~$0.000099 / 시간 (33% 할인)

Reserved (3년):
- ~53% 할인
```

### Reserved 적합 조건
- 12개월 이상 안정적 워크로드
- 기본 사용량(baseline)이 명확
- baseline은 Reserved, 스파이크는 On-Demand 또는 Auto Scaling

---

## 비용 절감 전략

### 1. 항목 크기 최소화
```typescript
// Bad: 불필요한 속성 저장
{ userId: "123", name: "Kim", email: "...", fullHistory: [...], rawPayload: {...} }

// Good: 필요한 것만, 큰 데이터는 S3로
{ userId: "123", name: "Kim", email: "...", historyUrl: "s3://..." }
```

### 2. GSI 프로젝션 최적화
```json
// Bad: ALL (모든 속성 복제 → 비용 2배)
"Projection": { "ProjectionType": "ALL" }

// Good: 필요한 속성만
"Projection": {
  "ProjectionType": "INCLUDE",
  "NonKeyAttributes": ["status", "createdAt"]
}

// Best: 키만 (나머지는 테이블에서 GetItem)
"Projection": { "ProjectionType": "KEYS_ONLY" }
```

### 3. 읽기 최적화
```typescript
// Eventually Consistent (기본, 비용 절반)
const result = await dynamodb.query({
  ConsistentRead: false,  // 기본값
  ...params
});

// ProjectionExpression으로 필요한 속성만
const result = await dynamodb.get({
  Key: { PK: "USER#123", SK: "METADATA" },
  ProjectionExpression: "name, email, #s",
  ExpressionAttributeNames: { "#s": "status" }
});
```

### 4. 배치 작업 활용
```typescript
// 개별 GetItem × 25 → BatchGetItem 1회
const result = await dynamodb.batchGet({
  RequestItems: {
    "my-table": {
      Keys: items.map(id => ({ PK: `USER#${id}`, SK: "METADATA" }))
    }
  }
});

// 개별 PutItem × 25 → BatchWriteItem 1회
await dynamodb.batchWrite({
  RequestItems: {
    "my-table": items.map(item => ({ PutRequest: { Item: item } }))
  }
});
```

### 5. TTL 활용 (무료 삭제)
```json
// 테이블에 TTL 속성 설정
{
  "TimeToLiveSpecification": {
    "AttributeName": "expiresAt",
    "Enabled": true
  }
}
```
```typescript
// 항목 저장 시 TTL 설정
const item = {
  PK: "SESSION#abc",
  SK: "METADATA",
  data: { ... },
  expiresAt: Math.floor(Date.now() / 1000) + 86400  // 24시간 후 삭제
};
```

### 6. DAX 캐시 (읽기 집중 워크로드)
```
비용 비교:
- DAX t3.medium: ~$0.06/시간 = ~$43/월
- 절약: 캐시 히트율 90%면 RCU 90% 절감

적합: 같은 항목을 반복 읽는 패턴 (상품 정보, 설정 등)
부적합: 쓰기 직후 읽기, 강력한 일관성 필요
```

---

## 비용 모니터링

### CloudWatch 메트릭
```
- ConsumedReadCapacityUnits / ProvisionedReadCapacityUnits → 사용률
- ConsumedWriteCapacityUnits / ProvisionedWriteCapacityUnits → 사용률
- ThrottledRequests → 용량 부족 신호
```

### Cost Explorer 태그
```json
// 테이블에 태그 추가 (비용 추적)
{
  "Tags": [
    { "Key": "Service", "Value": "order-service" },
    { "Key": "Environment", "Value": "production" },
    { "Key": "Team", "Value": "analytics" }
  ]
}
```
