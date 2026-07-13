---
name: project-context-manager
description: |
  프로젝트별 업무 컨텍스트를 체계적으로 정리, 축적, 요약하는 스킬.
  프로젝트 수행 과정의 의사결정, 아키텍처 설계, 기술 선택, 트러블슈팅 등을
  표준 포맷으로 기록하고, 포트폴리오/소개용 축약 버전을 자동 생성한다.
  트리거: 프로젝트 정리, 컨텍스트 기록, 포트폴리오, 프로젝트 소개, 프로젝트 요약,
  업무 정리, 아키텍처 정리, 의사결정 기록, ADR, 프로젝트 축약, 프로젝트 문서화
license: MIT
---

# Project Context Manager

프로젝트별 업무 컨텍스트를 **~/.kiro/projects/** 하위에 표준 포맷으로 축적·관리하는 스킬.

## 디렉토리 구조

```
~/.kiro/projects/
├── INDEX.md                    # 전체 프로젝트 인덱스 (자동 갱신)
├── STRUCTURE.md                # 디렉토리 구조 및 포맷 설명
├── {project-slug}/
│   ├── README.md               # 프로젝트 개요 (포트폴리오용 축약 버전)
│   ├── context.md              # 상세 컨텍스트 (풀 버전)
│   ├── decisions/              # 의사결정 기록 (ADR 포맷)
│   │   ├── 001-tech-stack.md
│   │   ├── 002-architecture.md
│   │   └── ...
│   ├── architecture/           # 아키텍처 관련 문서
│   │   ├── overview.md
│   │   ├── diagrams/           # 다이어그램 (mermaid, ASCII 등)
│   │   └── ...
│   └── timeline.md             # 주요 마일스톤/타임라인
└── ...
```

## 파일 포맷

### INDEX.md (자동 생성/갱신)

프로젝트 전체 목록을 한눈에 보여주는 인덱스.

```markdown
# Project Index

> 마지막 갱신: {YYYY-MM-DD}

| # | 프로젝트 | 기간 | 역할 | 핵심 기술 | 상태 |
|---|----------|------|------|-----------|------|
| 1 | [프로젝트명](./project-slug/README.md) | 2024.01~현재 | BE Lead | TypeScript, Kafka, EKS | 진행중 |
| 2 | ... | ... | ... | ... | 완료 |
```

### STRUCTURE.md (한 번 생성, 포맷 가이드)

디렉토리 구조와 각 파일의 역할, 작성 규칙을 설명하는 메타 문서.

### README.md (프로젝트별 — 축약 포트폴리오 버전)

YAML frontmatter + 간결한 소개. 이력서/포트폴리오에 바로 활용 가능.

```markdown
---
project: 프로젝트명
slug: project-slug
period: "2024.01 ~ 현재"
role: "Backend Lead"
team_size: 5
status: in-progress  # in-progress | completed | archived
tags: [TypeScript, Kafka, EKS, MSA]
---

# 프로젝트명

## 한줄 요약
IoT 디바이스 데이터를 실시간 수집·분석하는 클라우드 플랫폼 백엔드

## 핵심 성과
- 일 1억건 이벤트 처리 파이프라인 구축
- 레이턴시 p99 200ms → 50ms 개선
- 장애 대응 시간 30분 → 5분 단축

## 기술 스택
- **Runtime**: Node.js / TypeScript
- **Messaging**: Kafka (AWS MSK)
- **Orchestration**: Kubernetes (EKS)
- **Data**: DynamoDB, OpenSearch, PostgreSQL

## 아키텍처 요약
(2~3문장 또는 간단한 다이어그램 링크)

## 주요 의사결정
- [기술 스택 선정](./decisions/001-tech-stack.md)
- [아키텍처 패턴](./decisions/002-architecture.md)
```

### context.md (프로젝트별 — 상세 풀 버전)

업무 과정의 모든 컨텍스트를 상세히 기록.

```markdown
---
project: 프로젝트명
last_updated: "2024-03-15"
---

# 프로젝트 상세 컨텍스트

## 배경 & 목적
(왜 이 프로젝트가 시작됐는지, 비즈니스 컨텍스트)

## 요구사항
### 기능 요구사항
- ...
### 비기능 요구사항
- 처리량: 일 1억건
- 레이턴시: p99 < 100ms

## 아키텍처
### 전체 구조
(상세 설명, 컴포넌트 관계)

### 핵심 설계 포인트
- ...

## 기술 선택 & 이유
| 영역 | 선택 | 이유 | 대안 검토 |
|------|------|------|-----------|

## 트러블슈팅 & 교훈
### 이슈 1: ...
- 증상:
- 원인:
- 해결:
- 교훈:

## 팀 구성 & 역할
- 내 역할: ...
- 협업 방식: ...

## 성과 & 메트릭
- Before → After 비교
- 정량적 성과
```

### decisions/{NNN}-{title}.md (ADR 포맷)

```markdown
---
id: 1
title: 기술 스택 선정
date: "2024-01-15"
status: accepted  # proposed | accepted | deprecated | superseded
---

# ADR-001: 기술 스택 선정

## 컨텍스트
(의사결정이 필요한 배경)

## 결정
(무엇을 선택했는지)

## 근거
(왜 이 선택을 했는지)

## 대안
(검토했으나 선택하지 않은 것들과 이유)

## 결과
(이 결정의 영향, 후속 조치)
```

## 사용법

### 1. 새 프로젝트 컨텍스트 생성

```
"새 프로젝트 컨텍스트 만들어줘. 프로젝트명: IoT Analytics Platform"
```

→ 프로젝트 디렉토리 생성 + 템플릿 파일 초기화 + INDEX.md 갱신

### 2. 업무 과정에서 컨텍스트 추가

```
"IoT Analytics 프로젝트에 의사결정 기록해줘.
Kafka를 메시징으로 선택한 이유는..."
```

→ decisions/ 하위에 ADR 추가 + context.md 업데이트

### 3. 아키텍처 정리

```
"현재 설계한 아키텍처 정리해줘.
MSA 구조로, Egress-Worker 패턴 사용..."
```

→ architecture/ 하위에 문서 추가

### 4. 포트폴리오용 축약 버전 생성/갱신

```
"IoT Analytics 프로젝트 포트폴리오 버전 갱신해줘"
```

→ context.md 기반으로 README.md 자동 요약 생성

### 5. 전체 인덱스 갱신

```
"프로젝트 인덱스 갱신해줘"
```

→ 모든 프로젝트의 README.md frontmatter를 읽어 INDEX.md 재생성

## 동작 규칙

1. **포맷 일관성**: 모든 프로젝트는 동일한 디렉토리 구조와 파일 포맷을 따른다.
2. **자동 인덱싱**: 프로젝트 추가/변경 시 INDEX.md를 자동 갱신한다.
3. **점진적 축적**: 한 번에 모든 걸 채울 필요 없음. 점진적으로 내용을 추가한다.
4. **축약 ↔ 상세 분리**: README.md (축약)와 context.md (상세)는 분리 유지한다.
5. **slug 규칙**: 프로젝트 디렉토리명은 `lowercase-hyphen` 포맷.
6. **ADR 번호**: 프로젝트별 순차 번호 (001, 002, ...).
7. **상태 관리**: frontmatter의 status 필드로 프로젝트 상태를 추적한다.
8. **STRUCTURE.md**: 처음 1회만 생성하고, 포맷 변경 시에만 업데이트.

## 컨텍스트 참조

이 스킬은 `~/.kiro/steering/user-scope-config.md`의 환경 정보를 참조하여
팀명, 프로젝트 prefix 등을 자동으로 활용한다.
