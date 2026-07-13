---
name: coding-principles
description: |
  범용 소프트웨어 설계 원칙 가이드. DRY, SOLID, KISS, YAGNI, 재사용, 공용화,
  클린 코드, 테스트 원칙, 코드 리뷰 기준을 다룬다. 언어 무관하게 적용.
  트리거: 코드 작성, 리팩토링, 구조 설계, 중복, 재사용, 공용화, 모듈화, DRY, SOLID,
  클린 코드, 코드 리뷰, 설계 원칙, 아키텍처 패턴, OOP, 함수형, 테스트, 의존성
license: MIT
---

# Coding Principles (Language-Agnostic)

## 기존 코드 우선 (Reuse Before Create)

- **신규 구현 전, 반드시 기존 코드베이스를 탐색**
- 동일/유사 기능이 이미 있으면 재사용 또는 확장
- 없을 때만 새로 작성하되, 다른 곳에서도 쓸 수 있게 설계
- 공용 유틸/헬퍼 디렉토리 확인: `common/`, `shared/`, `utils/`, `lib/`

## DRY (Don't Repeat Yourself)

- 같은 로직이 2곳 이상이면 공용화 검토
- 3곳 이상이면 반드시 추출 (Rule of Three)
- 단, "우연히 비슷한 코드"는 무리하게 합치지 마 (의미적 중복만 제거)
- 추출 시 이름으로 "무엇을 하는지" 명확히

## SOLID

- **S**ingle Responsibility: 한 모듈/클래스 = 한 가지 변경 이유
- **O**pen-Closed: 확장에 열려있고, 수정에 닫혀있게
- **L**iskov Substitution: 하위 타입은 상위 타입 계약을 깨지 마
- **D**ependency Inversion: 상위 모듈이 하위 모듈에 의존하지 마 (추상에 의존)
- **I**nterface Segregation: 쓰지 않는 메서드에 의존하게 만들지 마

## KISS & YAGNI

- 가장 단순한 해결책부터 시작
- "나중에 필요할 것 같아서" 미리 만들지 마
- 추상화는 구체적 필요가 생겼을 때 도입
- 과도한 디자인 패턴 적용 주의 (패턴은 문제 해결 도구, 목적 아님)

## OOP vs FP (상황별 선택)

이건 정답이 아니라 **트레이드오프**:

| 상황 | OOP 적합 | FP 적합 |
|------|----------|---------|
| 상태가 많고 변이 필요 | ✅ 캡슐화 | |
| 데이터 변환 파이프라인 | | ✅ 순수 함수 체이닝 |
| 플러그인/확장 구조 | ✅ 다형성 | |
| 동시성/병렬 처리 | | ✅ 불변성 |
| 도메인 모델링 (DDD) | ✅ Entity/VO | |
| 유틸리티/헬퍼 | | ✅ 순수 함수 |

- 한 프로젝트에서 혼합 가능 (하이브리드가 현실적)
- 기존 코드베이스의 스타일을 먼저 따르고, 부분적으로 개선

## 공용화 판단 기준

공용으로 빼야 할 때:
- 3곳 이상에서 동일 로직 사용
- 비즈니스 로직이 아닌 인프라/유틸 성격
- 변경 시 한 곳만 고치면 되게 하고 싶을 때

공용화하지 말 것:
- 비즈니스 도메인에 강하게 결합된 로직 (컨텍스트별 분리 유지)
- 현재 1곳에서만 쓰이는 것 (premature abstraction)

## 의존성 방향

```
Presentation → Application → Domain ← Infrastructure
     ↓              ↓           ↑           ↑
   UI/API       Use Cases    Entities    DB/External
```

- 안쪽(Domain)은 바깥(Infra)을 모름
- 바깥이 안쪽에 의존 (의존성 역전)
- 외부 라이브러리/서비스는 adapter/port로 격리

## 네이밍 (범용)

- 의도를 드러내는 이름 (`processData` ❌ → `calculateMonthlyRevenue` ✅)
- 약어 최소화 (`usr` ❌ → `user` ✅)
- bool: `is-`, `has-`, `should-` prefix
- 컬렉션: 복수형 (`users`, `orders`)
- 함수: 동사로 시작 (`get`, `create`, `update`, `delete`, `validate`, `transform`)

## 에러 핸들링 (범용)

- 에러는 빨리 던지고, 가능한 가까이에서 처리
- 복구 가능한 에러 vs 불가능한 에러 구분
- 에러 메시지에 컨텍스트 포함 (무엇을 시도했고, 무엇이 실패했나)
- 에러 무시 금지 (catch 후 아무것도 안 하기 ❌)
- 로깅과 에러 전파는 분리 (둘 다 하거나, 전파만)

## 테스트 원칙 (범용)

- 새 기능 = 테스트 동반 (최소한 happy path)
- 버그 수정 = 재현 테스트 먼저, 그다음 fix
- 테스트 독립성: 순서/외부 상태에 의존하지 마
- 테스트 이름: "무엇이 어떤 조건에서 어떤 결과" 형식
- Mock은 경계(외부 의존성)에만 사용, 내부 구현 mock 최소화
- 테스트 피라미드: unit > integration > e2e

## 코드 리뷰 관점

리뷰 시 체크:
1. 기존에 같은 기능 있나? (중복 체크)
2. 이 변경의 영향 범위는? (사이드 이펙트)
3. 에러 케이스 처리했나?
4. 네이밍이 의도를 드러내나?
5. 테스트 충분한가?
6. 불필요한 복잡도 없나?

---

## 참고 소스

- [ramziddin/solid-skills](https://github.com/ramziddin/solid-skills) — SOLID + TDD skill
- [ertugrul-dmr/clean-code-skills](https://github.com/ertugrul-dmr/clean-code-skills) — Clean Code principles
- [labs42io/clean-code-typescript](https://github.com/labs42io/clean-code-typescript) — Clean Code for TS
