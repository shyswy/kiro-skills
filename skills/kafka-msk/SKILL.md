---
name: kafka-msk
description: |
  Apache Kafka / AWS MSK 메시징 패턴 가이드. Consumer/Producer 설계,
  Kafka Streams, KTable, exactly-once, partition 전략, consumer group을 다룬다.
  트리거: Kafka, MSK, consumer, producer, topic, partition, Kafka Streams, KTable, 메시징, 이벤트 스트리밍, 컨슈머, 프로듀서, 토픽, 파티션, 메시지 큐, 스트림 처리, 이벤트 드리븐
license: MIT
---

# Kafka / AWS MSK Patterns

## 기본 개념
- Topic: 메시지 카테고리 (파티션으로 분산)
- Partition: 순서 보장 단위, 병렬 처리 단위
- Consumer Group: 파티션을 그룹 내 consumer에 분배
- Offset: consumer의 읽기 위치

## Producer 설계
- Key 선택: 순서 보장이 필요한 단위 (예: orderId, userId)
- Key가 같으면 같은 파티션으로 → 순서 보장
- acks=all: 모든 replica 확인 (durability 최대)
- idempotent producer: enable.idempotence=true (중복 방지)
- batch.size + linger.ms: 처리량 vs 지연 트레이드오프
- compression.type: lz4 (속도) 또는 zstd (압축률)

## Consumer 설계
- auto.offset.reset: earliest (재처리) vs latest (최신만)
- enable.auto.commit=false: 수동 커밋 (처리 완료 후)
- max.poll.records: 한 번에 가져올 메시지 수 제한
- session.timeout.ms: consumer 장애 감지 시간
- 멱등 처리: 같은 메시지 재처리해도 결과 동일하게 설계
- Consumer Lag 모니터링: lag > threshold → 알림 (CloudWatch 또는 Burrow)

## Exactly-Once Semantics
- Transactional Producer + Consumer read_committed
- Kafka Streams: processing.guarantee=exactly_once_v2
- 외부 시스템 연동 시: Outbox 패턴 + 멱등 consumer

## Kafka Streams / KTable
- KStream: 이벤트 스트림 (unbounded)
- KTable: 최신 상태 (changelog, compacted topic)
- Join: KStream-KTable join (enrichment), KTable-KTable join (lookup)
- Windowing: Tumbling, Hopping, Session, Sliding
- State Store: RocksDB (로컬), changelog topic (복구용)
- Interactive Queries: 외부에서 state store 직접 조회

## Schema Registry
- Confluent Schema Registry 또는 AWS Glue Schema Registry
- Avro/Protobuf/JSON Schema 지원
- 호환성 모드: BACKWARD (기본), FORWARD, FULL
- Schema evolution: 필드 추가는 default 값 필수, 삭제는 FORWARD 호환 필요
- Subject naming: TopicNameStrategy (topic-value, topic-key)

## Dead Letter Queue (DLQ)
- 처리 실패 메시지를 별도 topic으로 라우팅
- DLQ topic 네이밍: {original-topic}.DLQ
- 재처리 전략: 수동 검토 후 원본 topic에 재발행
- 알림: DLQ에 메시지 유입 시 즉시 알림
- retention: 원본보다 길게 설정 (30일+)

## Consumer Group 전략
- 파티션 수 ≥ consumer 수 (초과 consumer는 idle)
- Rebalance 최소화: static membership (group.instance.id)
- Cooperative rebalancing: CooperativeStickyAssignor (점진적 재할당)
- Consumer 장애 시: session.timeout.ms 내 heartbeat 없으면 rebalance

## Topic 설계
- 네이밍: domain.entity.event (예: order.payment.completed)
- Partition 수: consumer 수의 배수, 변경 어려우므로 넉넉히
- Retention: 시간 기반 (7일 기본) 또는 크기 기반
- Compaction: KTable용 topic (최신 key만 유지)
- min.insync.replicas: 2 이상 (acks=all과 함께 durability 보장)

## AWS MSK 특화
- MSK Serverless vs Provisioned: 트래픽 예측 가능 → Provisioned
- MSK Connect: Kafka Connect managed service (S3 Sink, JDBC Source 등)
- IAM 인증: SASL/OAUTHBEARER
- 모니터링: CloudWatch metrics (UnderReplicatedPartitions, OfflinePartitionsCount)
- 클러스터 크기: partition 수 × replication factor ÷ broker 수
- Tiered Storage: 오래된 데이터를 S3로 자동 이동 (비용 절감)
- MSK Multi-VPC Connectivity: PrivateLink 기반 cross-VPC 접근

## 운영 판단 기준
- Partition 증설 시점 → references/operations.md
- Consumer scale-out 기준: lag > 처리량 × 허용지연
- Streams 인스턴스 수 = input 파티션 수 이하
- 상세 Producer/Consumer 패턴 → references/producer-patterns.md, references/consumer-patterns.md
- Streams/KTable 설계 → references/streams-ktable.md

---

## MCP 연동

### 사용 MCP: aws-cloudwatch
- 상태: ✅ 연동됨 (user-scope-config.md 참조)
- 활용 시나리오:
  - Consumer Lag 모니터링: `mcp_aws_cloudwatch_get_metric_data` (namespace: AWS/Kafka)
  - 브로커 상태 확인: UnderReplicatedPartitions, OfflinePartitionsCount
  - 알람 설정 확인: `mcp_aws_cloudwatch_get_active_alarms`
- 직접 Kafka 관리 (topic 생성, consumer group 조회 등)는 MCP 미지원 → CLI 또는 kafka-ui 사용
