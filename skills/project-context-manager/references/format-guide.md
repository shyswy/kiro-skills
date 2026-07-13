# Project Context Format Guide

이 문서는 `project-context-manager` 스킬이 생성하는 파일들의 상세 포맷 규칙을 정의한다.

## 파일별 역할

| 파일 | 역할 | 대상 독자 |
|------|------|-----------|
| `INDEX.md` | 전체 프로젝트 목록, 빠른 탐색 | 본인, 면접관 |
| `STRUCTURE.md` | 디렉토리/포맷 설명 (메타) | 본인, 기여자 |
| `{slug}/README.md` | 포트폴리오용 축약 (1~2페이지) | 면접관, 동료 |
| `{slug}/context.md` | 상세 컨텍스트 (무제한) | 본인, AI agent |
| `{slug}/decisions/*.md` | ADR (의사결정 기록) | 본인, 팀 |
| `{slug}/architecture/*.md` | 아키텍처 문서 | 본인, 팀 |
| `{slug}/timeline.md` | 마일스톤 타임라인 | 본인 |

## Frontmatter 스키마

### README.md frontmatter

```yaml
---
project: string          # 프로젝트 공식명
slug: string             # lowercase-hyphen, 디렉토리명과 동일
period: string           # "YYYY.MM ~ YYYY.MM" 또는 "YYYY.MM ~ 현재"
role: string             # 내 역할 (예: "Backend Lead", "Full-stack Developer")
team_size: number        # 팀 규모
status: enum             # in-progress | completed | archived
tags: string[]           # 핵심 기술 태그 (최대 8개)
company: string          # 회사/조직명 (선택)
---
```

### context.md frontmatter

```yaml
---
project: string          # README.md와 동일
last_updated: string     # "YYYY-MM-DD" 포맷
---
```

### decisions/{NNN}-{title}.md frontmatter

```yaml
---
id: number               # 순차 번호
title: string            # 의사결정 제목
date: string             # "YYYY-MM-DD"
status: enum             # proposed | accepted | deprecated | superseded
superseded_by: number    # status가 superseded일 때만 (대체한 ADR id)
---
```

## slug 생성 규칙

1. 프로젝트명을 영문 lowercase로 변환
2. 공백/특수문자 → hyphen
3. 연속 hyphen → 단일 hyphen
4. 최대 50자
5. 예시: "IoT Analytics Platform" → `iot-analytics-platform`

## 축약 버전 (README.md) 작성 규칙

- **분량**: 최대 A4 2페이지 분량 (약 1000자 내외)
- **구조**: 한줄요약 → 핵심성과(3~5개) → 기술스택 → 아키텍처요약 → 주요의사결정
- **성과**: 가능한 한 정량적 수치 포함 (Before → After)
- **기술스택**: 카테고리별 그룹핑 (Runtime, Data, Infra 등)
- **톤**: 간결하고 임팩트 있게. 불필요한 수식어 제거.

## 상세 버전 (context.md) 작성 규칙

- **분량 제한 없음**: 필요한 만큼 상세하게
- **점진적 축적**: 한 번에 완성할 필요 없음
- **섹션 순서**: 배경 → 요구사항 → 아키텍처 → 기술선택 → 트러블슈팅 → 팀 → 성과
- **코드 예시**: 필요 시 포함 가능
- **다이어그램**: mermaid 코드 블록 또는 architecture/ 디렉토리 참조

## ADR 작성 규칙

- **하나의 ADR = 하나의 의사결정**
- **번호**: 프로젝트별 순차 (001, 002, ...)
- **파일명**: `{NNN}-{짧은-영문-제목}.md`
- **필수 섹션**: 컨텍스트, 결정, 근거, 대안, 결과
- **status lifecycle**: proposed → accepted → (deprecated | superseded)

## INDEX.md 자동 갱신 규칙

1. 모든 프로젝트의 `README.md` frontmatter를 읽음
2. `status` 기준 정렬: in-progress → completed → archived
3. 같은 status 내에서는 period 내림차순 (최신 먼저)
4. 테이블 형식으로 재생성
5. 갱신 시각 자동 기록
