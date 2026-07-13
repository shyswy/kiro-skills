# repo-docs-sync

kiro-skills 레포의 메타 문서(README.md, ARCHITECTURE.md, ATTRIBUTION.md)를 skills/steering 변경 사항에 맞게 동기화하는 스킬.

## 트리거

- 스킬/steering 추가·삭제·이름변경 후
- "README 갱신", "문서 최신화", "인덱스 업데이트" 요청 시
- staged changes에 skills/ 또는 steering/ 변경이 포함된 경우

## 동작

1. `scripts/update-skills-index.sh` 실행 (README 스킬 목록 + 배지 자동 갱신)
2. 카테고리 분류 확인 (새 스킬이 올바른 카테고리에 매칭되는지)
3. ARCHITECTURE.md 구조 설명 동기화 여부 확인
4. ATTRIBUTION.md 출처 정합성 확인

## 연관 Hook

- `repo-docs-sync-reminder` — skills/steering 파일 수정 시 자동 리마인더
- `skill-index-updater` — SKILL.md 생성 시 자동 인덱스 갱신 (기존)

## 카테고리 분류 수정

새 스킬이 "Other"로 분류되면:
```bash
# scripts/update-skills-index.sh의 categorize_skill() 함수 수정
vim ~/.kiro/scripts/update-skills-index.sh
# 패턴 추가 후 재실행
bash ~/.kiro/scripts/update-skills-index.sh
```
