# Docker 이미지 최적화 체크리스트

## 이미지 크기 줄이기 단계별

### Step 1: Base Image 선택
| Base | 크기 | 용도 |
|------|------|------|
| node:20 | ~1GB | 개발/디버깅 |
| node:20-slim | ~200MB | 일반 프로덕션 |
| node:20-alpine | ~130MB | 경량 프로덕션 (권장) |
| gcr.io/distroless/nodejs20 | ~120MB | 최소 공격 표면 |

### Step 2: .dockerignore 최적화
```
node_modules
.git
.gitignore
dist
coverage
*.md
.env*
.vscode
.idea
docker-compose*.yml
Dockerfile*
.dockerignore
tests/
__tests__/
*.spec.ts
*.test.ts
```

### Step 3: Multi-Stage Build
```dockerfile
# Stage 1: 의존성 설치
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

# Stage 2: 빌드
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN pnpm build

# Stage 3: 프로덕션 의존성만
FROM node:20-alpine AS prod-deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

# Stage 4: 런타임 (최소)
FROM node:20-alpine AS runtime
WORKDIR /app
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

### Step 4: 레이어 캐시 최적화
```dockerfile
# 변경 빈도 낮은 것 먼저 (캐시 활용)
COPY package.json pnpm-lock.yaml ./   # 1. 의존성 정의 (거의 안 변함)
RUN pnpm install                       # 2. 설치 (lock 변경 시에만 재실행)
COPY . .                               # 3. 소스 코드 (자주 변함)
RUN pnpm build                         # 4. 빌드
```

### Step 5: 불필요한 파일 제거
```dockerfile
# 빌드 후 불필요한 파일 정리
RUN rm -rf src/ tests/ tsconfig.json .eslintrc*

# 또는 필요한 것만 복사 (multi-stage에서)
COPY --from=builder /app/dist ./dist
# src, tests, config 등은 복사하지 않음
```

---

## 레이어 분석

```bash
# 이미지 레이어별 크기 확인
docker history <image> --no-trunc

# dive 도구 (시각적 분석)
dive <image>

# 각 레이어에서 큰 파일 찾기
docker run --rm <image> du -sh /* | sort -rh | head -10
```

---

## 크기 비교 예시

| 최적화 단계 | 크기 |
|------------|------|
| node:20 + npm install + 소스 전체 | ~1.2GB |
| node:20-alpine + npm ci | ~400MB |
| multi-stage (prod deps only) | ~180MB |
| + .dockerignore + 불필요 파일 제거 | ~150MB |
| distroless + 빌드 결과만 | ~130MB |

---

## 빌드 속도 최적화

### BuildKit 캐시 마운트
```dockerfile
# npm 캐시를 마운트로 유지 (재빌드 시 다운로드 스킵)
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev

# pnpm store 캐시
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile
```

### 병렬 빌드 (독립 스테이지)
```dockerfile
# deps와 builder가 독립적이면 병렬 실행됨
FROM node:20-alpine AS frontend-builder
# ... frontend 빌드

FROM node:20-alpine AS backend-builder
# ... backend 빌드

FROM node:20-alpine AS runtime
COPY --from=frontend-builder /app/dist/public ./public
COPY --from=backend-builder /app/dist ./dist
```

---

## 프로덕션 체크리스트

- [ ] Multi-stage build 사용
- [ ] alpine 또는 distroless base
- [ ] .dockerignore 설정
- [ ] non-root user (USER node)
- [ ] HEALTHCHECK 포함
- [ ] 프로덕션 의존성만 (--omit=dev)
- [ ] 고정 태그 사용 (node:20.11.0-alpine, latest 금지)
- [ ] 불필요한 패키지 미설치
- [ ] 시크릿 미포함 (build-arg 또는 runtime env)
- [ ] 이미지 크기 < 200MB (Node.js 기준)
