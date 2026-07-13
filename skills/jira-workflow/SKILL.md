---
name: jira-workflow
description: |
  Jira 이슈/티켓 관리 자동화 스킬. commit→issue 연결, 코멘트 게시,
  story/task/epic 생성, 상태 전환, JQL 검색을 다룬다. Jira MCP 연동 필요.
  업무 보고/워크로그/스프린트 관리가 아닌, 개발 워크플로우 중 Jira 연동에 사용.
  트리거: jira, issue, ticket, 이슈 생성, 이슈 연결, 지라, 티켓, 커밋 연결,
  JQL, 이슈 검색, 상태 변경, epic 생성, task 생성, backlog
license: MIT
---

# Jira Workflow

코드 작업과 Jira 이슈를 연결하고 범용적인 Jira 업무 관리를 자동화한다.

> ⚠️ 팀 특화 워크로그/스프린트 관리는 `sprint-worklog-manager` 스킬 참조.
> 이 스킬은 프로젝트/팀에 무관한 범용 Jira 패턴을 다룬다.

## MCP 의존

### 사용 MCP: jira
- 상태: ✅ 연동됨 (user-scope-config.md 참조)
- 활용 도구:
  - `mcp_jira_get_issue` — 이슈 상세 조회
  - `mcp_jira_search_issues` — JQL 검색
  - `mcp_jira_create_story` — Story 생성
  - `mcp_jira_create_subtask` — Sub-task 생성
  - `mcp_jira_create_epic` — Epic 생성
  - `mcp_jira_update_issue` — 이슈 필드 수정
  - `mcp_jira_add_worklog` — 워크로그 추가
  - `mcp_jira_get_worklogs` — 워크로그 조회
  - `mcp_jira_add_comment` — 코멘트 추가
  - `mcp_jira_get_transitions` — 전환 가능 상태 조회
  - `mcp_jira_transition_issue` — 상태 전환
  - `mcp_jira_get_sprint` — 스프린트 조회
  - `mcp_jira_get_projects` — 프로젝트 목록

## 기능

### 1. Commit → Issue 연결
1. 현재 branch명에서 issue key 추출 (예: feature/PROJ-123-description → PROJ-123)
2. git log에서 최근 커밋 메시지 수집
3. 사용자에게 확인: "PROJ-123에 커밋 요약을 코멘트로 달까?"
4. 승인 시 `mcp_jira_add_comment`로 코멘트 게시

### 2. Story/Task 작성
사용자 요청 시 Jira issue 생성:
- `mcp_jira_create_story`: Story 생성
- `mcp_jira_create_subtask`: Sub-task 생성
- `mcp_jira_create_epic`: Epic 생성

필수 필드: summary, description
선택 필드: priority, labels, sprint, story points, epic_link

### 3. Worklog 기록
```
"PROJ-123에 3시간 기록해줘"
→ mcp_jira_add_worklog(issue_key="PROJ-123", time_spent="3h", category="개발")
```

### 4. Sprint 현황
- `mcp_jira_get_sprint`로 현재 스프린트 조회
- JQL로 스프린트 내 이슈 검색
- 상태별 분류 (To Do / In Progress / Done)

### 5. Issue 검색
- "내 이슈 보여줘" → JQL: `assignee = currentUser() AND status != Done`
- "이번 스프린트 이슈" → JQL: `sprint in openSprints()`
- 자유 JQL 지원: `mcp_jira_search_issues`

### 6. 상태 전환
1. `mcp_jira_get_transitions`로 가능한 전환 확인
2. `mcp_jira_transition_issue`로 상태 변경
3. resolution 필드 필요 시 함께 전달

### 7. Agile Backlog 일괄 생성
대규모 기능 계획 시:
- `mcp_jira_create_agile_backlog`로 Epic + Stories + Sub-tasks 일괄 생성
- 요구사항 기반으로 구조화된 백로그 자동 생성

## Branch → Issue Key 추출 규칙
- feature/PROJ-123-description → PROJ-123
- hotfix/PROJ-456 → PROJ-456
- PROJ-789-some-work → PROJ-789
- 패턴: /([A-Z]+-\d+)/

## 참고
- user-scope-config.md의 프로젝트 prefix로 기본 프로젝트 결정
- 팀 특화 워크로그/스프린트 관리 → `sprint-worklog-manager` 스킬
