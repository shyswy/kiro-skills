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
- **자동 갱신**: 프로젝트 추가/변경 시 project-context-manager 스킬이 업데이트
- **정렬 규칙**: in-progress → completed → archived, 같은 상태 내 최신 먼저
- **수동 편집 금지**: 스킬이 관리하므로 직접 수정하지 않기

### {project-slug}/README.md
- **포트폴리오용 축약**: 이력서, 소개, 면접에 바로 활용
- **분량**: A4 2페이지 이내 (~1000자)
- **YAML frontmatter 필수**: project, slug, period, role, team_size, status, tags

### {project-slug}/context.md
- **상세 풀 버전**: 분량 무제한, 업무 과정 전체 기록
- **점진적 축적**: 한 번에 완성하지 않아도 됨
- **AI 참조용**: 이후 대화에서 프로젝트 맥락 파악에 활용

### {project-slug}/decisions/
- **ADR (Architecture Decision Record)** 포맷
- 하나의 파일 = 하나의 의사결정
- 번호: 프로젝트별 순차 (001, 002, ...)
- 파일명: `{NNN}-{짧은-영문-제목}.md`

### {project-slug}/architecture/
- 전체 구조, 컴포넌트 관계, 데이터 흐름
- diagrams/ 하위에 mermaid 또는 ASCII art

### {project-slug}/timeline.md
- 주요 마일스톤과 날짜
- 프로젝트 진행 과정 요약

## 규칙

1. **디렉토리명 = slug**: lowercase-hyphen (최대 50자)
2. **frontmatter 필수**: 모든 .md 파일은 YAML frontmatter 포함
3. **축약 ↔ 상세 분리**: README.md와 context.md는 항상 별도 유지
4. **INDEX.md 자동 관리**: 수동 편집 X, 스킬이 갱신
5. **slug 생성**: 프로젝트명 영문 lowercase + hyphen (예: "IoT Platform" → `iot-platform`)
