---
inclusion: fileMatch
fileMatchPattern: "*.ts,*.tsx,*.js,*.jsx"
---

# TypeScript/JavaScript Rules

## 코드 스타일
- strict mode 필수 (`"strict": true`)
- any 사용 금지, unknown 또는 구체 타입 사용
- interface 우선 (type은 union/intersection에만)
- barrel export(index.ts) 남용 금지

## 비동기
- async/await 기본, .then() 체이닝 지양
- Promise.all로 병렬 처리, 순차 필요 시에만 for-of + await
- 에러는 try-catch로 감싸고 타입 가드 적용

## 모듈 설계
- 파일당 하나의 명확한 export 목적 (→ 범용 원칙은 `coding-principles` 참조)
- 순환 의존 금지
- 외부 의존성은 adapter 패턴으로 격리

## 네이밍
- 변수/함수: camelCase
- 클래스/인터페이스/타입: PascalCase
- 상수: UPPER_SNAKE_CASE
- 파일: kebab-case.ts

## 에러 처리
- 커스텀 에러 클래스 사용 (extends Error)
- 에러 메시지에 context 포함 (어떤 작업, 어떤 입력)
- 외부 API 호출은 반드시 에러 핸들링
