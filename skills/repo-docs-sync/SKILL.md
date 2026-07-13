---
name: repo-docs-sync
description: |
  kiro-skills 레포의 메타 문서(README.md, ARCHITECTURE.md, ATTRIBUTION.md)를
  skills/steering 변경 사항에 맞게 동기화한다.
  스킬/steering 추가·삭제·이름변경 후, 또는 사용자가 "README 갱신", "문서 최신화",
  "인덱스 업데이트", "repo 정리", "skills 목록 업데이트" 등을 언급할 때 사용한다.
  staged changes나 최근 커밋에 skills/ 또는 steering/ 변경이 포함되어 있으면
  반드시 이 스킬을 활성화하여 문서 정합성을 확인해야 한다.
  트리거: 워크로그, worklog, 오늘 작업 기록 등과 무관.
  트리거: README 갱신, 문서 최신화, 인덱스 업데이트, repo 정리, skills 목록 업데이트,
  스킬 추가 후 정리, steering 변경 후 정리, 문서 동기화, docs sync, ARCHITECTURE 업데이트.
---

# Repo Docs Sync

kiro-skills 레포의 메타 문서를 skills/steering 변경에 맞춰 동기화하는 스킬.

## 언제 실행하나

- `skills/*/SKILL.md` 추가, 삭제, 이름 변경 후
- `steering/*.md` 추가, 삭제 후
- `ATTRIBUTION.md` 에 새 소스 추가 후
- 사용자가 "README 갱신", "문서 최신화", "인덱스 업데이트" 요청 시
- git staged changes에 skills/ 또는 steering/ 변경이 포함된 경우

## 동기화 체크리스트

아래 항목을 순서대로 확인하고, 불일치가 있으면 수정한다.

### 1. README.md — 스킬 인덱스 갱신

```bash
bash ~/.kiro/scripts/update-skills-index.sh
```

이 스크립트가 하는 일:
- `<!-- SKILLS_START -->` ~ `<!-- SKILLS_END -->` 사이 교체
- 배지 숫자 업데이트 (Skills-N, Steering-N)
- 카테고리별 분류 + description 추출

**스크립트 실행 후 수동 확인:**
- 새 스킬이 올바른 카테고리에 분류되었는지
- `categorize_skill()` 함수의 case 패턴에 매칭 안 되면 "Other"로 빠짐
  → 필요 시 `scripts/update-skills-index.sh`의 `categorize_skill()` 수정

### 2. README.md — 카테고리 분류 규칙

현재 `update-skills-index.sh`의 분류 로직:

| 패턴 | 카테고리 |
|------|----------|
| `aws-*`, `api-gateway`, `supabase-postgres`, `terraform-skill` | AWS & Cloud |
| `k8s-*`, `docker-*`, `helm-*`, `gitops-*`, `observability` | Platform & Infra |
| `kafka-*`, `elasticsearch-*`, `dynamodb`, `rdb-*`, `iot-*` | Data & Messaging |
| `typescript-*`, `nodejs-*`, `api-design`, `architecture`, `git-*`, `coding-principles` | Development |
| `java-*`, `kotlin-*`, `spring-*` | Development |
| `jira-*`, `sprint-*`, `knowledge-*`, `scope-*`, `skill-*`, `project-*` | Workflow & Management |

**새 스킬이 기존 패턴에 매칭 안 될 때:**
1. `scripts/update-skills-index.sh`의 `categorize_skill()` 함수에 패턴 추가
2. 스크립트 재실행

### 3. ARCHITECTURE.md — 구조 설명 동기화

확인할 항목:
- **디렉토리 구조 예시** (섹션 8): 새로운 디렉토리 패턴이 생겼으면 추가
  - 예: `references/` 외에 `rules/` 패턴을 사용하는 스킬이 생겼다면 언급
- **3-Tier 스킬 전략** (섹션 4): 새 Tier 1/2 소스가 추가되었으면 예시 업데이트
- **자동화 도구 표** (섹션 5): 새 스크립트나 hook 추가 시 반영

### 4. ATTRIBUTION.md — 출처 정합성

확인할 항목:
- 새 스킬에 외부 소스가 있으면 해당 Tier 섹션에 추가되어 있는지
- Tier 분류 기준:
  - **Tier 1**: 공식/검증 소스를 그대로 설치 (있는 그대로 사용)
  - **Tier 2**: 커뮤니티 소스를 fork + 커스터마이징
  - **Tier 3**: 순수 커스텀 (외부 소스 없음 → ATTRIBUTION 불필요)

### 5. version.json (선택)

major 변경(스킬 대량 추가/삭제, 구조 변경)이면 버전 bump 고려.

## 스크립트 실행 불가 시 수동 절차

bash 4+ 없는 환경이라면:

1. `skills/` 디렉토리에서 public 스킬 수 세기 (`_` prefix 제외)
2. `steering/` 디렉토리에서 public steering 수 세기
3. README.md의 배지 숫자 직접 수정
4. Skills by Category 섹션에서 누락/삭제된 스킬 반영

## 주의사항

- `_` prefix 스킬/steering은 private → README에 노출하지 않음
- 스크립트는 `<!-- SKILLS_START -->` ~ `<!-- SKILLS_END -->` 마커 사이만 건드림
- README의 나머지 섹션(Installation, Compatibility 등)은 보존됨
- ARCHITECTURE.md는 수동 판단 필요 (자동화 대상 아님)
