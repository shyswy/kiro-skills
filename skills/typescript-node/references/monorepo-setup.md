# Monorepo 설정 가이드

## pnpm Workspace

### 기본 구조
```
my-monorepo/
├── pnpm-workspace.yaml
├── package.json            # root (scripts, devDependencies)
├── turbo.json              # Turborepo 설정
├── tsconfig.base.json      # 공유 TS 설정
├── packages/
│   ├── shared-types/       # @org/shared-types
│   ├── utils/              # @org/utils
│   └── config/             # @org/config (eslint, tsconfig)
├── apps/
│   ├── api/                # @org/api (NestJS)
│   ├── worker/             # @org/worker (Kafka consumer)
│   └── admin/              # @org/admin (React)
└── tools/
    └── scripts/            # 빌드/배포 스크립트
```

### pnpm-workspace.yaml
```yaml
packages:
  - 'packages/*'
  - 'apps/*'
  - 'tools/*'
```

### Root package.json
```json
{
  "name": "my-monorepo",
  "private": true,
  "scripts": {
    "build": "turbo run build",
    "test": "turbo run test",
    "lint": "turbo run lint",
    "dev": "turbo run dev --parallel"
  },
  "devDependencies": {
    "turbo": "^2.0.0",
    "typescript": "^5.4.0"
  }
}
```

### 패키지 간 의존성
```json
// apps/api/package.json
{
  "name": "@org/api",
  "dependencies": {
    "@org/shared-types": "workspace:*",
    "@org/utils": "workspace:*"
  }
}
```

---

## Turborepo 설정

### turbo.json
```json
{
  "$schema": "https://turbo.build/schema.json",
  "globalDependencies": ["**/.env.*local"],
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**"]
    },
    "test": {
      "dependsOn": ["build"],
      "inputs": ["src/**", "test/**"]
    },
    "lint": {
      "dependsOn": ["^build"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    }
  }
}
```

### 핵심 개념
- `^build`: 의존하는 패키지의 build 먼저 실행
- `outputs`: 캐시할 빌드 산출물
- `inputs`: 변경 감지 대상 (이것만 바뀌면 재실행)
- Remote Cache: Vercel 또는 자체 서버로 팀 간 캐시 공유

### 필터 실행
```bash
# 특정 패키지만
pnpm turbo run build --filter=@org/api

# 변경된 패키지만 (Git diff 기반)
pnpm turbo run build --filter=...[HEAD~1]

# 특정 패키지 + 의존성
pnpm turbo run build --filter=@org/api...
```

---

## 공유 패키지 구조

### @org/shared-types
```
packages/shared-types/
├── package.json
├── tsconfig.json
└── src/
    ├── index.ts          # barrel export
    ├── user.ts
    ├── order.ts
    └── common.ts
```

```json
// package.json
{
  "name": "@org/shared-types",
  "version": "0.0.0",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "scripts": {
    "build": "tsc",
    "lint": "eslint src/"
  }
}
```

### @org/utils
```typescript
// packages/utils/src/index.ts
export { retry } from './retry';
export { logger } from './logger';
export { validate } from './validate';
```

---

## TypeScript 설정

### tsconfig.base.json (root)
```json
{
  "compilerOptions": {
    "strict": true,
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true
  }
}
```

### 앱별 tsconfig.json
```json
// apps/api/tsconfig.json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src",
    "paths": {
      "@org/shared-types": ["../../packages/shared-types/src"],
      "@org/utils": ["../../packages/utils/src"]
    }
  },
  "include": ["src/**/*"],
  "references": [
    { "path": "../../packages/shared-types" },
    { "path": "../../packages/utils" }
  ]
}
```

---

## Docker 빌드 (Monorepo)

### pnpm + Docker (효율적 레이어 캐시)
```dockerfile
FROM node:20-alpine AS base
RUN corepack enable && corepack prepare pnpm@latest --activate

FROM base AS deps
WORKDIR /app
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY packages/shared-types/package.json ./packages/shared-types/
COPY packages/utils/package.json ./packages/utils/
COPY apps/api/package.json ./apps/api/
RUN pnpm install --frozen-lockfile

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/shared-types/node_modules ./packages/shared-types/node_modules
COPY --from=deps /app/apps/api/node_modules ./apps/api/node_modules
COPY . .
RUN pnpm turbo run build --filter=@org/api

FROM node:20-alpine AS runner
WORKDIR /app
COPY --from=builder /app/apps/api/dist ./dist
COPY --from=builder /app/apps/api/node_modules ./node_modules
USER node
CMD ["node", "dist/main.js"]
```

### Turborepo prune (최적화)
```bash
# 특정 앱에 필요한 파일만 추출
turbo prune @org/api --docker

# 결과: out/ 디렉토리에 필요한 것만
# out/json/ — package.json들
# out/full/ — 소스 코드
```

---

## CI/CD 통합

### GitLab CI (Monorepo)
```yaml
stages:
  - install
  - build
  - test
  - deploy

install:
  stage: install
  script:
    - pnpm install --frozen-lockfile
  cache:
    key: pnpm-$CI_COMMIT_REF_SLUG
    paths:
      - node_modules/
      - .turbo/

build:
  stage: build
  script:
    - pnpm turbo run build --filter=...[origin/main]
  # 변경된 패키지만 빌드

test:
  stage: test
  script:
    - pnpm turbo run test --filter=...[origin/main]

deploy-api:
  stage: deploy
  script:
    - pnpm turbo run deploy --filter=@org/api
  only:
    changes:
      - apps/api/**
      - packages/**
```
