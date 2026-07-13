---
name: knowledge-publish
description: |
  Skills 내용을 외부 플랫폼(Confluence, GitLab, GitHub, Notion)에 단방향 publish하는 스킬.
  변경된 스킬만 diff 비교 후 업데이트. 사용자 요청 시에만 동작.
  민감 정보 자동 필터링 후 publish.
  트리거: collab 퍼블리시, 지식 공유, 문서 게시, GitHub 공유, GitLab push, skills 배포, 컨플루언스, 노션, 문서 동기화, publish
license: MIT
---

# Knowledge Publish

skills를 외부 플랫폼에 단방향 publish한다. Source of truth는 항상 로컬 skills 파일.

## 핵심 원칙
- 사용자 요청 시에만 동작 (자동 아님)
- 변경된 스킬만 업데이트 (전체 재작성 X)
- 멀티 타겟 지원 (config 기반)
- **민감 정보 필터링 후 publish** (토큰, URL, 내부 정보 제거)

## 민감 정보 필터링

### publish 전 반드시 제거할 항목
- auth token, API key, PAT (패턴: `ghp_*`, `glpat-*`, `xoxb-*`, `Bearer *`)
- 내부 URL (사내 GitLab, Jira, Confluence 주소)
- IP 주소, 포트 번호 (내부 인프라)
- 사원번호, 이메일, 개인 식별 정보
- mcp.json 내용 (토큰, 서버 주소 포함)
- user-scope-config.md의 "현재 환경" 섹션 (내부 URL 포함)

### 필터링 규칙
1. publish 대상 콘텐츠에서 위 패턴 스캔
2. 발견 시 `[REDACTED]` 또는 `(내부 정보 제거됨)`으로 치환
3. 치환된 항목 목록을 사용자에게 보여주고 확인 요청
4. 확인 후 publish 진행

### target별 필터링 수준
- **GitLab/GitHub (public)**: 최대 필터링 — 내부 URL, 토큰, 사내 정보 전부 제거
- **Confluence (사내)**: 최소 필터링 — 토큰/credential만 제거, 내부 URL은 유지
- **Notion (개인)**: 필터링 없음 또는 토큰만 제거

### 커스텀 필터 패턴 (config.yaml)

```yaml
sensitive_patterns:
  - pattern: "https://gitlab\\.company\\.com"
    replace: "https://gitlab.example.com"
  - pattern: "glpat-[A-Za-z0-9_-]+"
    replace: "[GITLAB_TOKEN]"
```

## 동작 흐름

1. 사용자가 publish 요청
2. config.yaml에서 활성화된 target 확인
3. 각 target별로:
   a. 로컬 skill 파일 내용 읽기
   b. **민감 정보 필터링 적용** (target의 filter_level에 따라)
   c. 필터링 결과 사용자에게 표시 ("3개 항목이 마스킹됩니다")
   d. 사용자 확인 후 target 플랫폼의 기존 내용과 비교
   e. 변경된 것만 업데이트
4. changelog에 변경 이력 추가

## Target별 동작

### GitLab (GitLab MCP — 권장)
- **MCP 사용**: gitlab-mcp (mcp_gitlab_* 도구)
- 로컬 clone 불필요, remote에 직접 파일 생성/수정
- 동작 순서:
  1. `mcp_gitlab_get_file_contents`로 remote 파일 현재 내용 확인
  2. 로컬 skill 내용과 비교 (변경 감지)
  3. 변경된 파일만:
     - 파일 없으면 → `mcp_gitlab_create_file` (새 파일 + 커밋)
     - 파일 있으면 → `mcp_gitlab_update_file` (수정 + 커밋)
  4. commit_message: "chore: update {skill-name} skill"
  5. branch: config의 branch (기본 main)
- MR 생성 옵션: 사용자가 원하면 별도 branch → MR 생성 가능
  - `mcp_gitlab_create_branch` → 파일 수정 → `mcp_gitlab_create_merge_request`

### Confluence (collab MCP)
- **MCP 사용**: collab-mcp (mcp_collab_* 도구)
- user-scope-config.md에서 space key, parent page 참조
- 동작 순서:
  1. `mcp_collab_search_pages`로 기존 페이지 확인
  2. 없으면 `mcp_collab_create_page`
  3. 있으면 내용 비교 후 `mcp_collab_update_page`
- 변경 감지: 페이지 본문과 로컬 SKILL.md 내용 비교

### GitHub (git CLI)
- git add → commit → push
- 변경된 파일만 커밋
- **public 레포 시 strict 필터링 필수**

### Notion (향후)
- Notion MCP 연동 시 활성화
- database에 각 skill을 page로 관리

## 사용 예시

```
"kafka-msk skill만 GitLab에 push해줘"
→ strict 필터링 → gitlab MCP로 해당 파일만 update_file

"전체 skills GitLab에 퍼블리시해줘"
→ 변경된 스킬만 감지 → strict 필터링 → 마스킹 항목 표시 → 확인 후 일괄 push

"kafka-msk skill만 collab에 퍼블리시해줘"
→ moderate 필터링 → Confluence 페이지 업데이트

"전체 skills collab 퍼블리시"
→ 변경된 스킬만 찾아서 일괄 업데이트

"MR로 올려줘"
→ 새 branch 생성 → 변경 파일 push → MR 생성
```

## 설정 파일

config.yaml 위치: ~/.kiro/skills/knowledge-publish/config.yaml

```yaml
targets:
  gitlab:
    enabled: true
    mcp: gitlab-mcp
    project_id: "shyswy/kiro-skills-platform-engineer"
    branch: main
    filter_level: strict
  confluence:
    enabled: true
    mcp: collab-mcp
    space_key: "~username"
    parent_page: "AI Skills Knowledge Base"
    filter_level: moderate
  github:
    enabled: false
    repo: "shyswy/kiro-skills-platform-engineer"
    branch: main
    filter_level: strict
  notion:
    enabled: false
    filter_level: minimal

sensitive_patterns:
  - pattern: "glpat-[A-Za-z0-9_-]+"
    replace: "[GITLAB_TOKEN]"
  - pattern: "ghp_[A-Za-z0-9]+"
    replace: "[GITHUB_TOKEN]"
  - pattern: "Bearer [A-Za-z0-9._-]+"
    replace: "Bearer [REDACTED]"
```

## 참조
- user-scope-config.md steering의 환경 정보 참조
- scope-manager skill로 target 설정 변경 가능
