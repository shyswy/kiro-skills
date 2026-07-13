---
name: gitops-cicd
description: |
  GitLab CI/CD 파이프라인, ArgoCD GitOps 배포 전략, ECR 이미지 관리 가이드.
  환경별 배포, rollback, canary/blue-green 패턴을 다룬다.
  트리거: GitLab CI, ArgoCD, ECR, pipeline, GitOps, CD, 배포, rollback, 파이프라인, 자동배포, 롤백, canary, blue-green, 지속적 배포
license: MIT
---

# GitOps & CI/CD Patterns

## GitOps 원칙
- Git = Single Source of Truth (인프라/앱 상태)
- 선언적 설정 (desired state)
- 자동 동기화 (drift detection → reconciliation)
- Pull 기반 배포 (ArgoCD가 Git 감시 → 클러스터 적용)

## 파이프라인 구조 (GitLab CI)
```
stages:
  - lint
  - test
  - build
  - publish
  - deploy
```
- lint: eslint, prettier, hadolint
- test: unit + integration
- build: docker build (multi-stage)
- publish: ECR push (태그: commit SHA + latest)
- deploy: ArgoCD sync trigger 또는 manifest 업데이트

## ArgoCD 배포 전략

### App-of-Apps 패턴
- 루트 Application이 하위 Application들을 관리
- 환경별 분리: apps/dev/, apps/staging/, apps/prod/

### 디렉토리 구조
```
k8s-manifests/
├── base/              # 공통 manifest
├── overlays/
│   ├── dev/
│   ├── staging/
│   └── prod/
└── argocd/
    └── applications/
```

### Sync 전략
- Auto Sync: dev/staging
- Manual Sync: prod (승인 후)
- Sync Wave: 순서 제어 (DB → App → Ingress)

## 배포 패턴
- Rolling Update: 기본, 점진적 교체
- Blue-Green: 두 환경 전환 (즉시 롤백 가능)
- Canary: 일부 트래픽만 새 버전으로 (Argo Rollouts)

## Rollback
- ArgoCD: History → Rollback to revision
- Helm: helm rollback <release> <revision>
- 이미지 태그 기반: 이전 SHA 태그로 manifest 수정 → auto sync

## ECR 이미지 관리
- 태그 전략: git SHA (immutable) + semantic version
- Lifecycle Policy: untagged 이미지 30일 후 삭제
- 취약점 스캔: ECR 기본 스캔 또는 trivy

---

## MCP 연동

### 사용 MCP: gitlab-mcp + bitbucket-mcp
- 상태: user-scope-config.md 참조

#### GitLab (gitlab-mcp)
- 활용 도구:
  - `mcp_gitlab_list_pipelines` — 파이프라인 목록/상태 조회
  - `mcp_gitlab_get_pipeline` — 파이프라인 상세
  - `mcp_gitlab_list_pipeline_jobs` — job 목록
  - `mcp_gitlab_get_job_trace` — job 로그 확인
  - `mcp_gitlab_retry_pipeline` — 실패 파이프라인 재시도
  - `mcp_gitlab_create_pipeline` — 파이프라인 수동 트리거
  - `mcp_gitlab_get_file_contents` — .gitlab-ci.yml 조회
  - `mcp_gitlab_update_file` — CI 설정 수정

#### Bitbucket (bitbucket-mcp)
- 활용 도구:
  - `mcp_bitbucket_list_pull_requests` — PR 목록 조회
  - `mcp_bitbucket_get_diff` — PR diff 확인
  - `mcp_bitbucket_list_repositories` — 저장소 목록
  - `mcp_bitbucket_list_branches` — 브랜치 목록
- ⚠️ Bitbucket Server는 GitLab CI 같은 내장 CI/CD가 없음
  - Jenkins, GitHub Actions 등 외부 CI와 연동하는 구조
  - ArgoCD manifest repo가 Bitbucket에 있을 경우 파일 조회/수정 가능

### MCP 미연동 시
GitLab/Bitbucket MCP가 연동되지 않은 경우:
1. "해당 MCP가 연동되지 않았어. scope-manager 스킬로 설정할 수 있어." 안내
2. .gitlab-ci.yml 작성/수정은 로컬 파일 편집으로 가능
3. 파이프라인 조회/트리거는 MCP 연동 필수임을 안내
