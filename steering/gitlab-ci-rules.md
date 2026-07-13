---
inclusion: fileMatch
fileMatchPattern: ".gitlab-ci*"
---

# GitLab CI Rules

## 구조
- stages 순서: lint → test → build → deploy
- job명은 동사:목적어 (예: build:docker, deploy:staging)
- extends 또는 !reference로 중복 제거
- include로 공통 템플릿 분리

## 캐싱
- node_modules, .npm 캐시 활용
- cache key는 lock 파일 해시 기반

## Docker 빌드
- kaniko 또는 docker-in-docker 사용
- 이미지 태그: $CI_COMMIT_SHORT_SHA 또는 semantic version
- ECR push 시 aws-cli 인증 포함

## 배포
- staging → production 순서
- production은 manual trigger (when: manual)
- environment 설정으로 배포 추적
- rollback 가능한 구조 (ArgoCD sync 또는 이전 태그 재배포)

## 보안
- 시크릿은 CI/CD Variables (masked, protected)
- 스크립트에 토큰/비밀번호 하드코딩 금지
