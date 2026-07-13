---
name: scope-manager
description: |
  User scope 환경 관리 스킬. 회사/팀 변경, token 갱신, MCP 연동 설정, publish target 관리 등
  user-scope-config.md steering을 업데이트하고 관련 설정을 일괄 변경한다.
  트리거: 환경 변경, 회사 바꿨어, token 갱신, 설정 업데이트, scope 관리, MCP 연동, 팀 변경, URL 변경, 설정 초기화
license: MIT
---

# Scope Manager

user-scope-config.md (steering, always)를 중심으로 환경 설정을 관리한다.

## 핵심 원칙
- user-scope-config.md가 모든 환경 정보의 single source
- 이 파일을 수정하면 모든 skill이 자동으로 최신 환경 참조
- MCP 설정은 ~/.kiro/settings/mcp.json에 위치

## 기능

### 1. 환경 마이그레이션
사용자가 회사/팀을 변경했을 때:
1. user-scope-config.md의 URL, 팀명, prefix 업데이트
2. mcp.json 내 관련 MCP 서버 URL 변경 안내
3. token 갱신 필요 여부 확인

### 2. Token 갱신
token 만료 또는 변경 시:
1. mcp.json에서 해당 MCP 서버의 env/token 위치 안내
2. 갱신 절차 가이드 (PAT 생성 URL 등)
3. user-scope-config.md의 연동 상태 업데이트

### 3. MCP 연동 관리
새 MCP 추가 또는 기존 MCP 설정 변경:
1. mcp.json에 서버 설정 추가/수정
2. user-scope-config.md의 MCP 연동 상태 업데이트
3. 연동 테스트 안내

### 4. Skills 상태 점검
설치된 공식 스킬 버전 확인:
1. 현재 설치된 Tier 1 스킬 목록 확인
2. 원본 레포 최신 버전과 비교 (가능한 경우)
3. 업데이트 필요 시 install 스크립트 재실행 안내

### 5. Publish Target 관리
knowledge-publish의 target 추가/제거:
1. knowledge-publish/config.yaml 수정
2. 새 target의 MCP 연동 확인
3. user-scope-config.md 반영

## 참조 파일
- steering: ~/.kiro/steering/user-scope-config.md
- MCP 설정: ~/.kiro/settings/mcp.json
- publish config: ~/.kiro/skills/knowledge-publish/config.yaml

---

## MCP 설정 가이드

다른 스킬에서 "MCP 미연동" 상태로 이 스킬로 안내된 경우의 처리 흐름.

### Jira MCP 설정
```json
// ~/.kiro/settings/mcp.json에 추가
{
  "mcpServers": {
    "jira": {
      "command": "...",
      "args": ["..."],
      "env": {
        "JIRA_URL": "https://jira.company.com",
        "JIRA_API_TOKEN": "your-token"
      }
    }
  }
}
```
설정 후: user-scope-config.md의 Jira MCP 상태를 ✅로 업데이트

### GitLab MCP 확인/재설정
- 현재 상태: ~/.kiro/settings/mcp.json → gitlab-mcp 확인
- token 만료 시: GitLab → Settings → Access Tokens에서 재발급
- URL 변경 시: mcp.json의 env 수정 + user-scope-config.md 업데이트

### CloudWatch MCP 확인
- 현재 상태: ~/.kiro/settings/mcp.json → aws-cloudwatch 확인
- AWS credentials 필요 (AWS_PROFILE 또는 env)

### 새 MCP 추가 일반 흐름
1. 사용자에게 필요한 정보 확인 (URL, token 등)
2. mcp.json에 서버 설정 추가
3. user-scope-config.md의 MCP 연동 상태 업데이트
4. "MCP 서버가 추가됐어. Kiro를 재시작하거나 MCP 서버 뷰에서 reconnect해줘." 안내
