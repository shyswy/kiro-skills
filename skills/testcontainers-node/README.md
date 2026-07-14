# testcontainers-node

> Testcontainers로 Node.js 통합 테스트 환경 구축 패턴

## When to Use
- PostgreSQL/OpenSearch/Kafka 통합 테스트 설정
- Component test 환경 구축
- 테스트 격리 전략 설계
- CI에서 Docker 기반 테스트 실행

## What It Covers
- @testcontainers/postgresql, kafka, elasticsearch 설정
- Jest 연동 (describe-level lifecycle)
- DDL 로드, Seed 데이터, TRUNCATE 격리
- CI 환경 Docker-in-Docker 대응
- 테스트 격리 전략 비교

## Attribution
- Tier: 3 (직접 작성)
