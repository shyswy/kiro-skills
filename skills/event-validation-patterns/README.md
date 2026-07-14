# event-validation-patterns

> 메시징 Consumer 이벤트 검증 + 변환 파이프라인 패턴

## When to Use
- Kafka/SQS consumer에서 이벤트 페이로드 검증
- Raw event → Domain model 변환 설계
- Validation 실패 처리 전략 결정
- Schema versioning / upcasting

## What It Covers
- validate → transform → handle 파이프라인 구조
- Joi / Zod 양쪽 패턴 + 선택 기준
- Validation 실패 처리 전략 (Skip, DLQ, Retry)
- Schema versioning (envelope, upcasting)
- 테스트 패턴 (유효/무효 fixture)

## Attribution
- Tier: 3 (직접 작성)
