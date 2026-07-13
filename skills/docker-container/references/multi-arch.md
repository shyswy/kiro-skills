# 멀티 아키텍처 빌드 가이드

## 왜 필요한가?
- EKS에서 ARM (Graviton) 인스턴스 사용 시 비용 20~40% 절감
- 개발 환경 (Apple Silicon M1/M2) ↔ 프로덕션 (AMD64) 호환
- 하나의 이미지 태그로 양쪽 아키텍처 지원

---

## Docker Buildx 기본

### 빌더 생성
```bash
# 멀티 플랫폼 빌더 생성
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap
```

### 멀티 아키텍처 빌드 + Push
```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag $ECR_REGISTRY/my-app:latest \
  --tag $ECR_REGISTRY/my-app:$SHA \
  --push \
  .
```

### 결과: Manifest List
```bash
# 확인
docker manifest inspect $ECR_REGISTRY/my-app:latest
# → amd64, arm64 두 이미지가 하나의 태그에 연결됨
# → docker pull 시 자동으로 맞는 아키텍처 선택
```

---

## Dockerfile 멀티 아키텍처 대응

### 기본 (대부분 자동 동작)
```dockerfile
# node:20-alpine은 이미 멀티 아키텍처 지원
FROM node:20-alpine
# → buildx가 타겟 플랫폼에 맞는 base 자동 선택
```

### 아키텍처별 분기 (네이티브 바이너리 필요 시)
```dockerfile
FROM node:20-alpine AS builder
ARG TARGETPLATFORM
ARG TARGETARCH

# 아키텍처별 다른 바이너리 다운로드
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      wget https://example.com/tool-arm64; \
    else \
      wget https://example.com/tool-amd64; \
    fi
```

### Native 모듈 주의 (node-gyp)
```dockerfile
# bcrypt, sharp 등 native 모듈은 타겟 아키텍처에서 빌드해야 함
# buildx가 QEMU 에뮬레이션으로 처리 (느림)

# 빠른 대안: 순수 JS 대체 라이브러리 사용
# bcrypt → bcryptjs
# sharp → 별도 스테이지에서 빌드
```

---

## CI에서 멀티 아키텍처 빌드

### GitLab CI
```yaml
build:multiarch:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  variables:
    DOCKER_BUILDKIT: "1"
  before_script:
    - docker buildx create --use --name multiarch
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker buildx build
      --platform linux/amd64,linux/arm64
      --tag $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHORT_SHA
      --tag $ECR_REGISTRY/$ECR_REPO:latest
      --cache-from type=registry,ref=$ECR_REGISTRY/$ECR_REPO:cache
      --cache-to type=registry,ref=$ECR_REGISTRY/$ECR_REPO:cache,mode=max
      --push
      .
```

### 빌드 시간 최적화
```bash
# QEMU 에뮬레이션은 느림 (arm64 빌드가 amd64 머신에서 3~5배 느림)
# 해결: 네이티브 빌더 사용 (각 아키텍처 머신에서 빌드)

docker buildx create --name multiarch \
  --node amd64-builder --platform linux/amd64 \
  ssh://user@amd64-host

docker buildx create --name multiarch --append \
  --node arm64-builder --platform linux/arm64 \
  ssh://user@arm64-host
```

---

## EKS Graviton (ARM) 배포

### Node Group 혼합 (AMD64 + ARM64)
```yaml
# Karpenter NodePool
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: mixed-arch
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64", "arm64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
      nodeClassRef:
        name: default
```

### Pod에서 아키텍처 지정 (필요 시)
```yaml
# 특정 아키텍처 강제 (멀티 아키텍처 이미지 미지원 시)
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
```

### 비용 비교 (ap-northeast-2)
| 인스턴스 | 아키텍처 | vCPU | Memory | 시간당 비용 |
|----------|---------|------|--------|------------|
| m5.xlarge | AMD64 | 4 | 16GB | $0.208 |
| m6g.xlarge | ARM64 | 4 | 16GB | $0.166 (20% 저렴) |
| m7g.xlarge | ARM64 | 4 | 16GB | $0.175 (16% 저렴) |
