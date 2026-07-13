# kotlin-jpa-entity

> Kotlin + JPA Entity 설계 가이드 — data class 금지, identity/equality, N+1 방지, ORM 트랩

## When to Use

- Kotlin JPA Entity 생성/리뷰
- N+1, LazyInitializationException 진단
- equals/hashCode 전략, uniqueness constraint
- data class vs regular class 선택

## What It Covers

- Entity 설계 규칙 (data class 금지, no-arg plugin)
- Identity와 Equality (ID 기반 비교, stable hashCode)
- Uniqueness Constraints (DB + Application 이중 방어)
- Query & Fetch 규칙 (N+1 방지, EntityGraph, JOIN FETCH)
- Common ORM Traps (bidirectional, orphanRemoval, lazy load triggers)

## Attribution

- Source: [Kotlin/kotlin-agent-skills](https://github.com/Kotlin/kotlin-agent-skills)
- License: Apache-2.0
- Tier: 1 (as-is)
- Author: JetBrains
