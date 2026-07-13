# Docker 보안 스캐닝 가이드

## Trivy (권장)

### 로컬 스캔
```bash
# 이미지 취약점 스캔
trivy image my-app:latest

# 심각도 필터 (HIGH, CRITICAL만)
trivy image --severity HIGH,CRITICAL my-app:latest

# 수정 가능한 취약점만
trivy image --ignore-unfixed my-app:latest

# JSON 출력 (CI 파싱용)
trivy image --format json --output results.json my-app:latest

# Dockerfile 스캔 (빌드 전 검증)
trivy config Dockerfile

# 파일시스템 스캔 (의존성 취약점)
trivy fs --scanners vuln .
```

### CI 통합 (GitLab CI)
```yaml
security:trivy:
  stage: test
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  variables:
    TRIVY_NO_PROGRESS: "true"
    TRIVY_CACHE_DIR: ".trivycache/"
  cache:
    paths:
      - .trivycache/
  script:
    # 이미지 스캔
    - trivy image
      --exit-code 1
      --severity HIGH,CRITICAL
      --ignore-unfixed
      $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
  allow_failure: false  # CRITICAL 발견 시 파이프라인 실패
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

### .trivyignore (허용 목록)
```
# 오탐 또는 수정 불가한 취약점 무시
CVE-2023-12345
CVE-2024-67890  # 다음 버전에서 수정 예정
```

---

## ECR 기본 스캔

### 설정
```json
// ECR Repository 생성 시
{
  "imageScanningConfiguration": {
    "scanOnPush": true
  }
}
```

### 스캔 결과 확인
```bash
aws ecr describe-image-scan-findings \
  --repository-name my-app \
  --image-id imageTag=latest \
  --region ap-northeast-2
```

### ECR Enhanced Scanning (Inspector)
- OS 패키지 + 프로그래밍 언어 패키지 모두 스캔
- 지속적 스캔 (새 CVE 발견 시 재스캔)
- EventBridge로 알림 연동

---

## 취약점 대응 절차

### 심각도별 대응
| 심각도 | SLA | 대응 |
|--------|-----|------|
| CRITICAL (CVSS 9.0+) | 24시간 내 | 즉시 패치 또는 base image 업데이트 |
| HIGH (CVSS 7.0-8.9) | 7일 내 | 다음 배포에 포함 |
| MEDIUM (CVSS 4.0-6.9) | 30일 내 | 정기 업데이트 시 |
| LOW (CVSS 0.1-3.9) | 90일 내 | 편의에 따라 |

### 대응 방법
```bash
# 1. Base image 업데이트 (가장 흔한 해결)
# Dockerfile에서 버전 올리기
FROM node:20.11.0-alpine  →  FROM node:20.12.0-alpine

# 2. 특정 패키지 업데이트 (alpine)
RUN apk upgrade --no-cache libcrypto3 libssl3

# 3. 의존성 업데이트 (npm/pnpm)
pnpm update --latest
# 또는 특정 패키지만
pnpm update lodash@latest
```

---

## Dockerfile 보안 Best Practices

### 1. Non-root User
```dockerfile
# 방법 1: 기존 user 사용
USER node  # node 이미지에 기본 포함

# 방법 2: 커스텀 user 생성
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
```

### 2. Read-only Filesystem
```dockerfile
# 런타임에 쓰기 필요한 디렉토리만 volume으로
VOLUME ["/tmp", "/app/logs"]
```
```bash
# 실행 시
docker run --read-only --tmpfs /tmp my-app
```

### 3. No New Privileges
```bash
docker run --security-opt=no-new-privileges my-app
```
```yaml
# K8s
securityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

### 4. Secret 관리
```dockerfile
# Bad: 이미지에 시크릿 포함
COPY .env /app/.env  # ❌

# Good: BuildKit secret (빌드 시에만 사용, 레이어에 남지 않음)
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm ci

# Good: 런타임 환경변수
ENV DATABASE_URL=""  # 실행 시 주입
```

### 5. 최소 패키지
```dockerfile
# Bad: 불필요한 도구 설치
RUN apk add --no-cache curl wget vim git  # ❌

# Good: 필요한 것만
RUN apk add --no-cache tini  # PID 1 문제 해결용만
ENTRYPOINT ["/sbin/tini", "--"]
```

---

## 이미지 서명 (Supply Chain Security)

### Cosign (Sigstore)
```bash
# 키 생성
cosign generate-key-pair

# 이미지 서명
cosign sign --key cosign.key $ECR_REGISTRY/my-app:$SHA

# 서명 검증
cosign verify --key cosign.pub $ECR_REGISTRY/my-app:$SHA
```

### CI에서 자동 서명
```yaml
sign:image:
  stage: publish
  script:
    - cosign sign --key env://COSIGN_KEY $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHORT_SHA
```

---

## 정기 스캔 자동화

```yaml
# 주간 스캔 (스케줄)
security:weekly-scan:
  stage: test
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
  script:
    - trivy image --severity HIGH,CRITICAL $ECR_REGISTRY/$ECR_REPO:latest
    # 결과를 Slack으로 알림
    - |
      if [ $? -ne 0 ]; then
        curl -X POST $SLACK_WEBHOOK -d '{"text":"⚠️ 취약점 발견: '$ECR_REPO'"}'
      fi
```
