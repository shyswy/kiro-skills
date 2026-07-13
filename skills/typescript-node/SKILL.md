---
name: typescript-node
description: |
  TypeScript/Node.js 개발 패턴 가이드. NestJS, Express, Fastify 프레임워크 패턴,
  모듈 설계, 비동기 처리, 에러 핸들링, 테스트 전략을 다룬다.
  트리거: TypeScript, Node.js, NestJS, Express, Fastify, npm, 모듈 설계, 비동기, 타입스크립트, 노드, 백엔드, 서버, DI, 의존성 주입, 에러 핸들링
license: MIT
---

# TypeScript / Node.js Patterns

## 프로젝트 구조 (Layered)
```
src/
├── modules/          # 도메인별 모듈
│   └── user/
│       ├── user.controller.ts
│       ├── user.service.ts
│       ├── user.repository.ts
│       └── user.dto.ts
├── common/           # 공통 유틸, 데코레이터
├── config/           # 환경 설정
└── main.ts
```

## 비동기 패턴
- I/O bound 작업은 항상 async/await
- CPU bound 작업은 worker_threads 또는 외부 큐로 분리
- 동시 실행: Promise.all (독립적), Promise.allSettled (실패 허용)
- 순차 실행이 필요한 경우만 for-of + await
- AbortController로 타임아웃/취소 처리
- AsyncLocalStorage: 요청 컨텍스트 전파 (correlation ID, user info)

## 에러 핸들링
- 도메인 에러 클래스 계층 구조 (AppError → NotFoundError, ValidationError 등)
- HTTP 레이어에서만 status code 매핑
- 비즈니스 로직은 도메인 에러만 throw
- unhandledRejection, uncaughtException 글로벌 핸들러 필수
- Result 패턴 (neverthrow): throw 대신 Result<T, E> 반환 (선택적)

## DI / IoC
- NestJS: @Injectable + constructor injection
- 순수 Node: tsyringe 또는 수동 factory 패턴
- 인터페이스 기반 의존성 (구현체 교체 용이)

## 설정 관리
- env validation: zod 또는 class-validator
- config 모듈로 중앙 관리
- 환경별 분리: .env.development, .env.production
- 타입 안전: ConfigService<T> 제네릭

## Monorepo 패턴
- pnpm workspace: pnpm-workspace.yaml로 패키지 정의
- Turborepo: 빌드 캐싱, 의존성 기반 태스크 실행
- Nx: 영향 받은 프로젝트만 빌드/테스트
- 공유 패키지: @org/shared-types, @org/utils
- tsconfig paths: 패키지 간 참조 (references)

## ESM vs CJS
- 신규 프로젝트: ESM 기본 ("type": "module" in package.json)
- tsconfig: module=NodeNext, moduleResolution=NodeNext
- 확장자 명시: import from './util.js' (ESM에서 필수)
- CJS 호환: dynamic import()로 CJS 모듈 로드
- Dual package: exports 필드로 ESM/CJS 동시 지원

## 테스트
- unit: vitest 또는 jest, mock은 최소한으로
- integration: 실제 DB/외부 서비스 연동 (testcontainers)
- 테스트 파일: *.spec.ts (같은 디렉토리)
- E2E: supertest (HTTP), playwright (UI)

## 성능
- Fastify > Express (벤치마크 기준)
- Streaming: Node.js Streams로 대용량 데이터 처리
- Clustering: PM2 cluster mode 또는 Node.js cluster 모듈
- Memory leak 감지: --inspect + Chrome DevTools, clinic.js

---

## MCP 연동

이 스킬은 특정 MCP에 의존하지 않음. 코드 작성/리뷰/설계 가이드 목적.
- AWS Lambda 배포 시 → `aws-serverless-eda` 스킬 참조
- Docker 컨테이너화 시 → `docker-container` 스킬 참조
- CI/CD 파이프라인 시 → `gitops-cicd` 스킬 참조
