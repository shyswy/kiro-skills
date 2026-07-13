# Architecture & Design Decisions

이 문서는 kiro-skills 레포의 구조적 설계 결정과 그 이유를 기록한다.
"왜 이렇게 짰나" 복기용 + 외부 사용자 이해용.

---

## 1. 핵심 설계 원칙

### Source of Truth = `~/.kiro/`

```
~/.kiro/ (이 repo)
├── steering/    ← 규칙 원본 (Kiro native format)
├── skills/      ← 도메인 지식 원본 (agentskills.io standard)
└── scripts/     ← 다른 플랫폼으로 배포하는 도구
```

**결정 이유:**
- 주력 도구가 Kiro이므로 Kiro format을 원본으로 유지
- 다른 도구는 export 스크립트로 변환/symlink 배포
- "중립 형식(.ai/ 등)" 대신 "주력 도구 native + export" 방식 채택
- 이유: 중립 형식은 아무 도구도 직접 읽지 못해서 결국 양쪽 다 변환 필요 → 비효율

### Skills ≠ Steering (역할 분리)

| | Skills | Steering |
|---|---|---|
| **언제** | 키워드 매칭 시 on-demand | 항상 or 파일 열 때 자동 |
| **크기** | 큼 (도메인 전문 지식) | 작음 (규칙, 컨벤션) |
| **컨텍스트 비용** | 필요할 때만 로딩 (절약) | 항상 로딩됨 |
| **크로스 플랫폼** | agentskills.io (동일 형식) | 도구마다 형식 다름 |

**결정 이유:**
- Steering에 도메인 지식 넣으면 매 대화에 컨텍스트 낭비
- Skills로 분리하면 "Kafka 질문"할 때만 Kafka 지식 로딩 (progressive disclosure)

---

## 2. 크로스 플랫폼 전략

### Skills: Symlink (변환 불필요)

```
~/.kiro/skills/kafka-msk/SKILL.md    ← 원본
     ↓ symlink
~/.claude/skills/kafka-msk/SKILL.md  ← 같은 파일
~/.codex/skills/kafka-msk/SKILL.md   ← 같은 파일
```

**결정 이유:**
- agentskills.io가 업계 표준 → 모든 도구가 같은 SKILL.md 형식을 읽음
- 복사하면 drift (수정 후 재배포 안 하면 구버전 유지)
- symlink하면 수정 즉시 모든 도구에 반영

### Steering: 형식 변환 (export 스크립트)

```
~/.kiro/steering/typescript-rules.md
     ↓ export-for-platform.sh (변환)
.cursor/rules/typescript-rules.mdc     (globs frontmatter)
.github/instructions/typescript-rules.instructions.md  (applyTo frontmatter)
AGENTS.md (섹션으로 합침)
```

**결정 이유:**
- 도구마다 "조건부 로딩" 형식이 다름 (Kiro=fileMatchPattern, Cursor=globs, Copilot=applyTo)
- symlink 불가 → 변환 필수
- AGENTS.md로만 하면 "TS 파일 열 때 Docker 규칙도 로딩" 같은 컨텍스트 낭비 발생
- 도구별 변환으로 정밀한 조건부 로딩 유지

### 왜 `.ai/` common layer를 안 쓰나?

- `.ai/`는 아무 도구도 자동 탐색하지 않음 (표준 아님, 일부 sync 도구 컨벤션일 뿐)
- `AGENTS.md`가 진짜 표준 (Linux Foundation, 97K+ repos, 20+ 도구 네이티브)
- 네 steering/이 이미 source of truth 역할 → .ai/ 추가하면 이중 관리

---

## 3. Private/Public 분리

```
_prefix = private (gitignored)

skills/_sprint-worklog-manager/   ← 회사 특화, 미공개
steering/_user-scope-config.md    ← 개인 URL/토큰 포함

No prefix = public (GitHub 공개)

steering/user-scope-config.example.md  ← 템플릿만 공개
```

**결정 이유:**
- 하나의 repo로 공개/비공개 공존
- fork하는 사람은 `_` 파일 없어도 동작 (example 복사해서 사용)
- gitignore에 `skills/_*/`, `steering/_*.md` 패턴으로 일괄 관리

---

## 4. 3-Tier 스킬 전략

| Tier | 출처 | 예시 |
|------|------|------|
| **Tier 1** | 공식 소스 설치 | aws-serverless, terraform-skill, supabase-postgres |
| **Tier 2** | 커뮤니티 fork + 확장 | kafka-msk (lobehub base + AWS MSK 추가) |
| **Tier 3** | 순수 커스텀 | architecture, typescript-node, api-design |

**결정 이유:**
- 바퀴 재발명 방지 (좋은 공식 스킬 있으면 그대로 사용)
- 부족한 부분만 확장 (fork + 커스텀)
- ATTRIBUTION.md에 출처 명시 (라이선스 컴플라이언스)

---

## 5. 자동화

| 도구 | 역할 | 트리거 |
|------|------|--------|
| `scripts/update-skills-index.sh` | README.md 스킬 목록 갱신 | 수동 or CI |
| `scripts/validate-skills.sh` | SKILL.md 유효성 검사 | CI on push |
| `scripts/export-for-platform.sh` | 다른 플랫폼 배포 | 수동 |
| `.kiro/hooks/skill-index-updater` | SKILL.md 생성 시 자동 인덱싱 | Kiro IDE event |
| `cliff.toml` | CHANGELOG 자동 생성 | `git-cliff` 실행 시 |
| GitHub Actions | CI/CD | push to main |

---

## 6. Global vs Workspace 우선순위

```
Workspace (.kiro/ in project) > Global (~/.kiro/)
```

- 이 repo는 **Global** user-scope (모든 프로젝트에 적용)
- 프로젝트에서 같은 이름 파일을 만들면 자동 override
- Global: 개인 기본값 / Workspace: 팀/프로젝트 규칙

---

## 7. 호환성 설계

| 레이어 | 형식 | 호환 범위 |
|--------|------|-----------|
| Skills | agentskills.io (SKILL.md) | 30+ platforms |
| Steering (export) | 플랫폼별 변환 | 7 platforms |
| AGENTS.md (export) | Linux Foundation 표준 | 20+ platforms |
| Hooks | Kiro 전용 | Kiro only |

**결정 이유:**
- Skills를 agentskills.io 준수하면 별도 작업 없이 크로스 플랫폼
- Steering은 도구마다 달라서 export 스크립트로 대응
- Hooks는 Kiro 고유 기능이라 이식 불가 (대안 없음)

---

## 8. 디렉토리 구조 요약

```
~/.kiro/
├── .github/              # GitHub CI + templates
│   ├── workflows/        # validate-skills, update-readme
│   └── ISSUE_TEMPLATE/   # skill request template
├── .kiro/hooks/          # Kiro agent hooks
├── steering/             # Rules (Kiro native, always/fileMatch)
├── skills/               # Domain expertise (agentskills.io)
│   ├── {name}/SKILL.md   # Required
│   ├── {name}/README.md  # GitHub browsing
│   └── {name}/references/# Deep content (on-demand)
├── scripts/              # Automation
│   ├── install.sh        # Hybrid installer (profile-based)
│   ├── validate-skills.sh  # CI linter
│   ├── update-skills-index.sh  # README generator
│   └── export-for-platform.sh  # Cross-platform deployer
├── projects/             # Project context (managed by skill)
├── history/              # Archived work docs (gitignored)
├── settings/             # MCP configs (gitignored, secrets)
├── README.md             # Auto-generated index
├── CONTRIBUTING.md       # Fork/PR guide
├── CHANGELOG.md          # git-cliff generated
├── ATTRIBUTION.md        # Source credits
├── ARCHITECTURE.md       # This file
├── version.json          # Release metadata
├── cliff.toml            # Changelog config
└── LICENSE               # MIT
```
