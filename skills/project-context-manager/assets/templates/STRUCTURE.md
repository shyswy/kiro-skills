# Projects 디렉토리 구조

> 이 문서는 `~/.kiro/projects/` 디렉토리의 구조와 각 파일의 역할을 설명한다.

## 구조

```
~/.kiro/projects/
├── INDEX.md                        # 전체 프로젝트 인덱스 (자동 갱신)
├── STRUCTURE.md                    # 이 파일 (포맷 가이드)
├── {project-slug}/
│   ├── README.md                   # 포트폴리오용 축약 버전
│   ├── context.md                  # 상세 컨텍스트 (풀 버전)
│   ├── decisions/                  # 의사결정 기록 (ADR)
│   │   ├── 001-{title}.md
│   │   ├── 002-{title}.md
│   │   └── ...
│   ├── architecture/               # 아키텍처 문서
│   │   ├── overview.md
│   │   └── diagrams/
│   └── timeline.md                 # 마일스톤 타임라인
└── ...
```

## 파일 역할

### INDEX.md
- **자동 갱신**: 프로젝트 추가/변경 시 자동 업데이트
- **정렬**: 진행중 → 완료 → 아카이브 순, 같은 상태 내에서 최신 먼저
- **용도**: 빠른 탐색, 전체 현황 파악

### {project-slug}/README.md
- **포트폴리오용**: 이력서, 소개, 면접에 바로 활용 가능
- **분량**: A4 2페이지 이내 (~1000자)
- **구성**: 한줄요약 → 핵심성과 → 기술스택 → 아키텍처요약 → 주요의사결정

### {project-slug}/context.md
- **상세 기록**: 분량 제한 없이 업무 과정 전체를 기록
- **점진적 축적**: 한 번에 완성하지 않아도 됨
- **AI 참조용**: 이후 대화에서 프로젝트 맥락 파악에 활용

### {project-slug}/decisions/
- **ADR 포맷**: Architecture Decision Record
- **하나의 파일 = 하나의 의사결정**
- **이력 관리**: status로 생명주기 추적

### {project-slug}/architecture/
- **설계 문서**: 전체 구조, 컴포넌트 관계, 데이터 흐름
- **다이어그램**: mermaid, ASCII art, 또는 이미지 참조

### {project-slug}/timeline.md
- **마일스톤**: 주요 이벤트와 날짜
- **용도**: 프로젝트 진행 과정 요약

## 규칙

1. 디렉토리명 = slug (lowercase-hyphen)
2. 모든 .md 파일은 YAML frontmatter 포함
3. 포트폴리오 버전(README.md)과 상세 버전(context.md)은 항상 분리
4. INDEX.md는 수동 편집하지 않음 (스킬이 자동 관리)
