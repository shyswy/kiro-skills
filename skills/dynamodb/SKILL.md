---
name: dynamodb
description: |
  DynamoDB 테이블 설계, 키 전략, GSI/LSI, single-table design, 용량 관리 가이드.
  WCU/RCU 계산, TTL, 트랜잭션, DAX 캐싱 패턴을 다룬다.
  트리거: DynamoDB, partition key, sort key, GSI, LSI, single-table, WCU, RCU, TTL, 다이나모, NoSQL, 키 설계, 용량 관리, 테이블 설계
license: MIT
---

# DynamoDB Design Patterns

## 키 설계 원칙
- Partition Key: 높은 카디널리티, 균등 분산
- Sort Key: 범위 쿼리, 계층 구조 표현
- 핫 파티션 방지: 랜덤 suffix 또는 시간 기반 분산

## Single-Table Design
- 엔티티별 PK/SK 패턴:
  - User: PK=USER#userId, SK=METADATA
  - Order: PK=USER#userId, SK=ORDER#orderId
- GSI로 역방향 조회 (GSI1PK, GSI1SK)
- 오버로딩: 같은 테이블에 여러 엔티티
- 접근 패턴 먼저 정의 → 키 설계 (ERD 먼저 X)

## GSI / LSI
- GSI: 다른 파티션 키로 조회 (eventually consistent)
- LSI: 같은 파티션 키, 다른 정렬 키 (strongly consistent 가능)
- GSI 프로젝션: KEYS_ONLY, INCLUDE, ALL (비용 vs 성능 트레이드오프)
- Sparse Index: 특정 속성이 있는 항목만 GSI에 포함

## 용량 관리
- On-Demand: 트래픽 예측 불가 시
- Provisioned: 안정적 트래픽, 비용 최적화
- Auto Scaling 설정 (target utilization 70%)
- Reserved Capacity: 1년 이상 안정적 워크로드

## 쿼리 패턴
- Query > Scan (항상)
- begins_with, between으로 SK 범위 조회
- FilterExpression은 읽기 후 필터 (RCU 절약 안 됨)
- ProjectionExpression으로 필요한 속성만
- Limit + LastEvaluatedKey로 페이지네이션

## 트랜잭션
- TransactWriteItems: 최대 100개 항목, 4MB
- 멱등성 보장: ClientRequestToken 사용
- 조건부 쓰기: ConditionExpression
- 트랜잭션 비용: 일반 쓰기의 2배 WCU

## TTL
- 자동 삭제 (비용 없음, 48시간 내 삭제)
- 아카이브 필요 시 DynamoDB Streams → Lambda → S3
- TTL 속성: epoch seconds (Unix timestamp)

## DynamoDB Streams
- 변경 이벤트 캡처: INSERT, MODIFY, REMOVE
- Lambda 트리거: 실시간 반응 (집계, 알림, 복제)
- Cross-region replication: Global Tables의 기반
- Stream view type: NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES, KEYS_ONLY

## Global Tables
- Multi-region, active-active 복제
- 모든 리전에서 읽기/쓰기 가능
- 충돌 해결: last-writer-wins (timestamp 기반)
- 요구사항: Streams 활성화, On-Demand 또는 Auto Scaling

## Backup & Restore
- On-demand backup: 수동 스냅샷 (비용 발생)
- PITR (Point-in-Time Recovery): 최근 35일 내 임의 시점 복원
- Export to S3: 분석용 데이터 추출 (DynamoDB JSON 또는 Ion)

## DAX (캐싱)
- 읽기 집중 워크로드에 적합
- Eventually consistent reads만 캐시
- 쓰기 후 즉시 읽기 패턴에는 부적합
- Item cache + Query cache 분리
- TTL: item cache 5분 기본, query cache 5분 기본

---

## MCP 연동

### 사용 MCP: aws-cloudwatch
- 상태: ✅ 연동됨 (user-scope-config.md 참조)
- 활용 시나리오:
  - 테이블 메트릭 모니터링: `mcp_aws_cloudwatch_get_metric_data` (namespace: AWS/DynamoDB)
  - 주요 메트릭: ConsumedReadCapacityUnits, ConsumedWriteCapacityUnits, ThrottledRequests, SystemErrors
  - 핫 파티션 감지: SuccessfulRequestLatency 급증 확인
  - 알람: `mcp_aws_cloudwatch_get_active_alarms` (Throttle 알람 등)

### 참고
- DynamoDB 직접 관리 (테이블 생성, 항목 CRUD)는 MCP 미지원 → AWS CLI 또는 SDK 사용
- CDK/CloudFormation으로 테이블 정의 시 → `aws-cdk-development` 스킬 참조
