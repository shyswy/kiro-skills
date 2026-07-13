---
name: git-gitlab
description: |
  GitLab 기반 버전관리, MR 전략, branching 모델, 코드리뷰 가이드.
  Git 명령어 패턴과 GitLab 특화 워크플로우를 다룬다.
  트리거: git, gitlab, MR, merge request, branch, rebase, merge, 코드리뷰, 브랜치, 머지, 리베이스, 버전관리, 커밋, PR
license: MIT
---

# Git / GitLab Workflow

## Branching 전략
- main: 프로덕션 배포 브랜치
- develop: 통합 브랜치 (선택적)
- feature/PROJ-123-description: 기능 개발
- hotfix/PROJ-456-description: 긴급 수정
- release/v1.2.0: 릴리즈 준비

## Commit Convention
```
type(scope): subject

body (optional)

Refs: PROJ-123
```
- type: feat, fix, refactor, docs, test, chore, perf
- scope: 모듈/컴포넌트명
- subject: 50자 이내, 현재형

## MR (Merge Request) 전략
- 1 MR = 1 이슈 (branch명에 이슈 키 포함)
- description 템플릿: 변경 요약, 테스트 방법, 스크린샷
- self-review 후 리뷰 요청
- squash merge 기본 (깔끔한 히스토리)
- MR 제목 = commit message 형식

## Rebase vs Merge
- feature → develop/main: squash merge
- develop → feature (sync): rebase
- 공유 브랜치에서는 force push 금지

## 코드리뷰
- 로직 변경은 반드시 리뷰
- nit(사소한 것)과 blocker(필수 수정) 구분
- 24시간 내 리뷰 응답

## GitLab 특화
- /approve, /merge 슬래시 커맨드 활용
- CI 파이프라인 통과 필수 (merge check)
- protected branch 설정 (main, develop)

---

## MCP 연동

### 사용 MCP: gitlab-mcp + bitbucket-mcp
- 상태: user-scope-config.md 참조

#### GitLab (gitlab-mcp)
- 활용 도구:
  - `mcp_gitlab_list_merge_requests` — MR 목록 조회
  - `mcp_gitlab_create_merge_request` — MR 생성
  - `mcp_gitlab_get_merge_request_changes` — MR 변경 파일 확인
  - `mcp_gitlab_add_mr_comment` — MR 코멘트
  - `mcp_gitlab_list_branches` — 브랜치 목록
  - `mcp_gitlab_create_branch` — 브랜치 생성
  - `mcp_gitlab_compare_branches` — 브랜치 비교
  - `mcp_gitlab_list_commits` — 커밋 히스토리

#### Bitbucket (bitbucket-mcp)
- 활용 도구:
  - `mcp_bitbucket_list_pull_requests` — PR 목록 조회
  - `mcp_bitbucket_create_pull_request` — PR 생성
  - `mcp_bitbucket_get_diff` — PR 변경 파일 확인
  - `mcp_bitbucket_add_comment` — PR 코멘트
  - `mcp_bitbucket_list_branches` — 브랜치 목록
  - `mcp_bitbucket_list_repositories` — 저장소 목록

#### GitLab ↔ Bitbucket 매핑

| 기능 | GitLab | Bitbucket |
|------|--------|-----------|
| 코드 리뷰 | MR (Merge Request) | PR (Pull Request) |
| MR/PR 생성 | create_merge_request | create_pull_request |
| MR/PR 목록 | list_merge_requests | list_pull_requests |
| 변경 확인 | get_merge_request_changes | get_diff |
| 코멘트 | add_mr_comment | add_comment |
| 브랜치 | list_branches | list_branches |
| 커밋 | list_commits | list_commits (확인 필요) |

### MCP 미연동 시
GitLab/Bitbucket MCP가 연동되지 않은 경우:
1. "해당 MCP가 연동되지 않았어. scope-manager 스킬로 설정할 수 있어." 안내
2. git CLI 기반 fallback 제공 (push, branch, log 등)
3. MR/PR 생성 등 API 필요 기능은 MCP 연동 필수임을 안내
