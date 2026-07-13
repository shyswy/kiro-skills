# spring-data-jpa

> Spring Data JPA 패턴 가이드 — Entity 규칙, N+1 방지, Keyset Pagination, Batch Insert

## When to Use

- JPA Entity, Repository, Query 생성 시
- N+1 문제 진단/해결
- Pagination, Projection 패턴 결정
- Bidirectional relationship 설계

## What It Covers

- Entity Conventions (UUID, EnumType.STRING, static factory)
- N+1 Prevention (JOIN FETCH, @EntityGraph, Projections)
- Query Patterns (derived, JPQL, native, exists)
- Pagination (Pageable, Keyset/seek method)
- Bidirectional Relationships (양방향 동기화)
- Batch Inserts (JDBC batching, IDENTITY 주의)
- Gotchas (AI가 자주 하는 실수 9가지)

## Attribution

- Source: [rrezartprebreza/spring-boot-skills](https://github.com/rrezartprebreza/spring-boot-skills)
- License: MIT
- Tier: 1 (as-is)
