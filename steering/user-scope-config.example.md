# User Scope Config (EXAMPLE)

> ⚠️ 이 파일은 템플릿입니다. 실제 사용 시 `user-scope-config.md`로 복사 후 값을 채우세요.
> `user-scope-config.md`는 gitignore 처리되어 공개 레포에 올라가지 않습니다.

## 현재 환경
- GitLab: https://gitlab.your-company.com
- GitLab 네임스페이스: your-group
- GitLab Username: your.username
- Bitbucket: https://bitbucket.your-company.com
- Bitbucket 프로젝트: YOUR_PROJECT
- Bitbucket Username: your.username
- Jira: https://jira.your-company.com (프로젝트: PROJECT_KEY)
- Confluence: https://confluence.your-company.com
- Confluence Space Key: YOUR_SPACE
- 팀: Your Team Name
- 프로젝트 prefix: PROJECT_KEY

## MCP 연동 상태
- GitLab MCP: ✅ 연동됨 (gitlab-mcp)
- Bitbucket MCP: ❌ 미연동
- Jira MCP: ✅ 연동됨 (jira)
- Collab MCP: ❌ 미연동
- AWS CloudWatch MCP: ✅ 연동됨 (aws-cloudwatch, region: us-east-1)
- AWS Docs MCP: ✅ 연동됨 (aws-docs)

## Token 갱신 안내
- 토큰 저장 위치: `~/.kiro/settings/.env` (환경변수로 관리, gitignored)
- mcp.json은 `${ENV_VAR}` 참조만 포함 (평문 토큰 없음)
- 갱신 시: `~/.kiro/settings/.env` 수정 후 shell 재시작
- AWS: `~/.aws/credentials` (profile: default)
