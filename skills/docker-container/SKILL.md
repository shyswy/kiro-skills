---
name: docker-container
description: |
  Docker 컨테이너 빌드/최적화/배포 가이드. multi-stage build, 이미지 최적화,
  ECR 연동, security scanning, registry 관리를 다룬다.
  트리거: Docker, 컨테이너, 이미지, multi-stage, ECR, registry, 이미지 최적화, 도커, 빌드, Dockerfile, 컨테이너화, 경량화, 보안 스캔
license: MIT
---

# Docker Container Patterns

## Multi-Stage Build
```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

## 이미지 최적화
- alpine 기반 (최소 크기)
- .dockerignore 필수: node_modules, .git, dist, *.md
- npm ci --omit=dev (프로덕션 의존성만)
- 레이어 캐시 활용: 변경 빈도 낮은 것 먼저 COPY
- distroless 이미지: 최소 공격 표면

## 보안
- non-root user (USER node, USER 1001)
- read-only filesystem (--read-only)
- no-new-privileges (security-opt)
- 취약점 스캔: trivy image scan, ECR 기본 스캔
- secrets: build-time은 --secret, runtime은 env/volume

## ECR 연동
- 인증: aws ecr get-login-password | docker login
- 태그 전략: commit SHA (immutable) + latest
- Lifecycle Policy: untagged 30일 삭제, 최근 N개만 유지
- Cross-region replication: 멀티 리전 배포 시

## docker-compose (로컬 개발)
- 서비스 의존성: depends_on + healthcheck
- 볼륨: 소스 코드 마운트 (hot reload)
- 네트워크: 서비스 간 통신용 bridge
- 환경변수: .env 파일 분리

## 성능
- BuildKit 활성화 (DOCKER_BUILDKIT=1)
- 병렬 빌드: multi-stage 독립 스테이지
- 캐시 마운트: --mount=type=cache,target=/root/.npm

---

## MCP 연동

### 사용 MCP: aws-cloudwatch
- 상태: ✅ 연동됨 (user-scope-config.md 참조)
- 활용 시나리오:
  - ECR 이미지 스캔 결과: CloudWatch Events로 알림 확인
  - 컨테이너 메트릭 (ECS/EKS 배포 시): ContainerInsights namespace

### 참고
- ECR 직접 관리 (push, lifecycle policy)는 MCP 미지원 → AWS CLI 사용
- CI/CD에서 Docker 빌드 시 → `gitops-cicd` 스킬 참조
- K8s 배포 시 → `k8s-eks` 스킬 참조
