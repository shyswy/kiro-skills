# nodejs-kafka

> kafkajs 기반 Node.js/TypeScript Kafka Consumer/Producer 구현 패턴

## When to Use
- kafkajs consumer/producer 코드 작성
- Kafka graceful shutdown (Node.js 환경)
- Batch processing + DLQ 패턴
- Event Envelope, Correlation ID 전파
- Consumer group 전략 설계

## What It Covers
- kafkajs 셋업 (MSK IAM SASL 포함)
- Consumer: Graceful shutdown, eachBatch, Retry + DLQ, Static membership
- Producer: Idempotent, Compression, Headers
- Event Envelope 표준 + Correlation ID 전파
- 운영: Health check, Structured logging

## Related Skills
- `kafka-msk` — 인프라/설계 레벨
- `architecture` → event-driven-patterns.md — 설계 패턴
- `contract-testing` — 이벤트 계약 테스트
- `testcontainers-node` — Kafka 통합 테스트

## Attribution
- Tier: 3 (직접 작성)
