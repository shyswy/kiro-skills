# spring-layered-architecture

> Spring Boot Layered Architecture 강제 — Controller/Service/Repository 분리, DTO 매핑 규칙

## When to Use

- Spring Boot 클래스 생성/수정 시
- Controller, Service, Repository, DTO, Mapper, Configuration 작성 시
- 레이어 간 책임 분리 확인

## What It Covers

- Layer Rules (Controller → Service → Repository)
- Controller Layer (HTTP only, no business logic)
- Service Layer (business logic, @Transactional, constructor injection)
- Repository Layer (data access only)
- DTO 분리 (Request/Response, Record, factory method)
- Mapper Pattern
- Configuration Layer
- Gotchas (AI가 자주 하는 실수)

## Attribution

- Source: [rrezartprebreza/spring-boot-skills](https://github.com/rrezartprebreza/spring-boot-skills)
- License: MIT
- Tier: 1 (as-is)
