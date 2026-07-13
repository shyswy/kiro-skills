# Repo-Specific Skill Creation Policy

이 문서는 kiro-skills 레포에서 skill-creator를 사용할 때 추가로 따라야 할 정책이다.
skill-creator의 기본 워크플로우에 아래 단계들을 삽입한다.

---

## 1. 외부 소스 체크 (Interview and Research 단계에 삽입)

새 스킬을 작성하기 **전에**, 반드시 아래 순서로 외부 소스를 조사한다:

### Step 1: 동일/유사 스킬 검색

다음 소스에서 동일 기능 스킬이 있는지 확인:
1. [lobehub.com/skills](https://lobehub.com/skills) — 커뮤니티 스킬 마켓
2. [agentskills/agentskills](https://github.com/agentskills/agentskills) — 공식 레지스트리
3. GitHub 검색: `"SKILL.md" + <domain keyword>`
4. [awslabs/agent-plugins](https://github.com/awslabs/agent-plugins) — AWS 공식
5. [VoltAgent/awesome-agent-skills](https://github.com/VoltAgent/awesome-agent-skills) — 큐레이션

### Step 2: 3-Tier 분류 결정

| Tier | 조건 | 액션 |
|------|------|------|
| **Tier 1** (그대로 사용) | 기능 100% 일치 + 라이선스 호환 (MIT/Apache-2.0) | 그대로 설치, ATTRIBUTION에 기록 |
| **Tier 2** (fork + 확장) | 기능 유사하나 부족/확장 필요 | base 참조하며 커스텀, ATTRIBUTION에 base 기록 |
| **Tier 3** (순수 커스텀) | 외부에 없음 | 직접 작성 |

### Step 3: 사용자 확인

조사 결과를 사용자에게 보고:
- "이미 [repo/skill-name]에 동일 기능이 있습니다. 그대로 쓸까요, 참고해서 새로 만들까요?"
- 라이선스 정보 함께 제시

---

## 2. ATTRIBUTION 업데이트

Tier 1 또는 Tier 2로 외부 소스를 참조한 경우:

1. `ATTRIBUTION.md`에 아래 형식으로 추가:
```markdown
| 스킬명 | 소스 | 라이선스 | 활용 방식 |
|--------|------|----------|-----------|
| new-skill | [author/repo](url) | MIT | Tier 2 base + 커스텀 확장 |
```

2. 스킬 내부에도 참조 명시 (SKILL.md 하단 또는 README.md):
```markdown
## Attribution
- Based on: [source](url) (License)
```

---

## 3. 스킬 완성 후 레포 정책 체크리스트

스킬 작성 완료 후, 아래를 확인/실행:

- [ ] `bash scripts/validate-skills.sh` 실행 (frontmatter 유효성)
- [ ] 스킬 디렉토리에 `README.md` 생성 (GitHub 열람용)
- [ ] Private 여부 판단: 회사 특화 내용이면 `_` prefix 사용
- [ ] ATTRIBUTION.md 업데이트 (외부 참조 시)
- [ ] workspace 파일 정리: eval 결과물은 `history/`로 이동하거나 삭제

---

## 4. 스킬별 README.md 템플릿

```markdown
# skill-name

> one-line description

## When to Use
- trigger keyword 1
- trigger keyword 2

## What It Covers
- topic 1
- topic 2

## References
- `references/xxx.md` — 상세 가이드

## Attribution
- Based on: [source](url) (License)
- Tier: 1|2|3
```

---

## 5. 출력 위치 규칙

- 스킬 생성 결과물: `~/.kiro/skills/<skill-name>/`
- eval workspace: `~/.kiro/history/<skill-name>-workspace/` (gitignored)
- 최종 스킬만 skills/에 남기고 workspace는 history로 이동
