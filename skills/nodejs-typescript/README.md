# nodejs-typescript

> Node.js + TypeScript 개발 패턴 가이드 — Type Stripping, async 패턴, streams, 에러 핸들링, 테스트, 성능

## When to Use

- Node.js, TypeScript, npm, async/await
- streams, ESM, CommonJS, pino
- 노드, 타입스크립트, 백엔드, 서버
- type stripping, tsconfig, graceful shutdown

## What It Covers

- TypeScript Type Stripping (Node.js 22.6+, 빌드 도구 없이 .ts 실행)
- Async Patterns (Promise.all, p-limit, AbortController)
- Error Handling (error codes, cause chain, factory pattern)
- Streams (pipeline, async generators, backpressure)
- Modules (ESM, file extensions, barrel exports)
- Testing (node:test, mocking, snapshot, EventEmitter timing)
- Flaky Tests 진단 (공유 상태, 포트 충돌, race conditions)
- Stuck Processes 진단 (why-is-node-running, deterministic teardown)
- Performance (piscina, connection pooling, memory leaks)
- Caching (lru-cache, async-cache-dedupe, Redis)
- Logging (pino, transports, redaction)
- Profiling (@platformatic/flame, autocannon, k6)
- Environment Configuration (--env-file, env-schema, Zod)
- Graceful Shutdown (close-with-grace, Kubernetes delays)

## Attribution

- Source: [mcollina/skills](https://github.com/mcollina/skills)
- Author: Matteo Collina (Node.js TSC)
- License: MIT
- Tier: 1 (as-is)
