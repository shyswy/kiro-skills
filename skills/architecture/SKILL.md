---
name: architecture
description: |
  시스템 아키텍처 설계 가이드. MSA, Event-Driven, DDD, Layered Architecture,
  Egress-Worker 패턴, ServiceInvoker, 바운더리 정의, 통신 패턴을 다룬다.
  트리거: 아키텍처, MSA, event-driven, DDD, layered, Egress-Worker, ServiceInvoker, 설계, 마이크로서비스, 이벤트 드리븐, 도메인 주도, 시스템 설계, 통신 패턴, 바운더리
license: MIT
---

# Architecture Patterns

## Layered Architecture
```
Controller → Service → Repository → Database
     ↓           ↓
   DTO        Domain Entity
```
- 각 레이어는 하위 레이어만 의존
- 도메인 로직은 Service 레이어에 집중
- Repository는 데이터 접근 추상화

## MSA 원칙
- 서비스 경계 = 비즈니스 도메인 경계 (Bounded Context)
- 서비스 간 통신: 동기(REST/gRPC) vs 비동기(이벤트)
- 데이터 소유권: 각 서비스가 자체 DB 소유
- 장애 격리: Circuit Breaker, Bulkhead, Retry

## Event-Driven Architecture
- 이벤트 발행: 도메인 이벤트 (OrderCreated, PaymentCompleted)
- 이벤트 소비: 느슨한 결합, 비동기 처리
- 이벤트 저장소: Kafka topic (retention 기반)
- 핵심 패턴: Outbox, Idempotent Consumer, Saga, CQRS, Event Sourcing
- 상세 패턴 + 코드 예시 → references/event-driven-patterns.md

### 패턴 선택 가이드
| 상황 | 추천 패턴 |
|------|-----------|
| DB 커밋 + 이벤트 원자성 보장 | Transactional Outbox |
| Consumer 중복 처리 방지 | Idempotent Consumer (event ID dedup) |
| 분산 트랜잭션 (3개 이하 서비스) | Saga — Choreography |
| 분산 트랜잭션 (4개+ 서비스, 복잡 보상) | Saga — Orchestration |
| 읽기/쓰기 모델 분리 | CQRS |
| 상태 변경 이력 전체 보존 | Event Sourcing |
| 스키마 변경 안전하게 | Event Schema Evolution (Backward compatible) |
| 처리 불가 메시지 격리 | Dead Letter Queue |

## DDD (Domain-Driven Design)
- Aggregate: 일관성 경계, 하나의 트랜잭션 단위
- Entity: 식별자로 구분, 생명주기 있음
- Value Object: 불변, 값으로 비교
- Domain Event: 도메인 상태 변경 알림
- Repository: Aggregate 단위 영속화

## Egress-Worker 패턴 (BC3.0)
- Egress: 외부 시스템 호출을 큐잉
- Worker: 큐에서 꺼내 실제 외부 호출 수행
- 장점: 외부 시스템 장애 격리, 재시도 용이, 순서 보장

## ServiceInvoker 패턴
- 서비스 간 호출을 추상화하는 레이어
- 인터페이스 기반: 동기/비동기 구현 교체 가능
- 공통 관심사 처리: 로깅, 메트릭, 타임아웃, 재시도

## 설계 결정 기준
- 동기 vs 비동기: 즉시 응답 필요? → 동기. 아니면 비동기.
- 이벤트 vs 커맨드: 발행자가 소비자를 모름 → 이벤트. 특정 대상 지시 → 커맨드.
- 모놀리스 vs MSA: 팀 규모, 배포 독립성, 도메인 복잡도로 판단.

---

## MCP 연동

이 스킬은 특정 MCP에 의존하지 않음. 아키텍처 설계/리뷰 가이드 목적.
- 관련 스킬 참조:
  - 메시징/이벤트: `kafka-msk`, `iot-messaging`
  - 인프라: `k8s-eks`, `aws-serverless-eda`
  - 데이터: `dynamodb`, `rdb-optimization`, `elasticsearch-opensearch`
  - API: `api-design`
