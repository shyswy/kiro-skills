---
inclusion: fileMatch
fileMatchPattern: "Dockerfile*,docker-compose*"
---

# Docker Rules

## Dockerfile
- multi-stage build 필수 (builder → runtime 분리)
- base image는 specific tag 사용 (latest 금지)
- non-root user로 실행 (USER node, USER appuser 등)
- COPY는 필요한 파일만 (불필요한 context 복사 금지)
- .dockerignore 필수 (node_modules, .git, dist 등)
- RUN 레이어 최소화 (&&로 체이닝)
- HEALTHCHECK 포함

## docker-compose
- version 명시 불필요 (compose v2+)
- 서비스명은 kebab-case
- 환경변수는 .env 파일 분리
- depends_on에 condition: service_healthy 사용
- volume mount는 명시적 경로
- network는 명시적으로 정의

## 보안
- secrets는 build-arg 또는 runtime env로 (이미지에 포함 금지)
- 불필요한 패키지 설치 금지
- 취약점 스캔 (trivy, snyk) 파이프라인에 포함
