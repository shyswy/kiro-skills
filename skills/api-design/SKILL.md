---
name: api-design
description: |
  REST/GraphQL API 설계 원칙, 버저닝, 에러 처리, OpenAPI 스펙 작성 가이드.
  엔드포인트 네이밍, 페이지네이션, 인증 패턴을 다룬다.
  트리거: API, REST, GraphQL, endpoint, OpenAPI, 스키마, 버저닝, 에러 응답, 엔드포인트, 페이지네이션, 인증, 상태코드, CRUD
license: MIT
---

# API Design Patterns

## REST 설계 원칙
- 리소스 중심 URL: /users, /users/{id}/orders
- HTTP 메서드 의미 준수: GET(조회), POST(생성), PUT(전체수정), PATCH(부분수정), DELETE
- 복수형 명사 사용: /users (O), /user (X)
- 동사 URL 지양: /getUser (X) → GET /users/{id} (O)

## 응답 형식
```json
{
  "data": {},
  "meta": { "page": 1, "totalPages": 10 }
}
```
에러:
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Email is required",
    "details": [{ "field": "email", "reason": "required" }]
  }
}
```

## HTTP Status Code
- 200: 성공 (GET, PUT, PATCH)
- 201: 생성 성공 (POST)
- 204: 성공, 본문 없음 (DELETE)
- 400: 클라이언트 요청 오류
- 401: 인증 필요
- 403: 권한 없음
- 404: 리소스 없음
- 409: 충돌 (중복 등)
- 422: 유효성 검증 실패
- 500: 서버 내부 오류

## 페이지네이션
- cursor 기반 (대용량, 실시간 데이터)
- offset 기반 (관리자 페이지, 작은 데이터셋)
- 응답에 next_cursor 또는 total_count 포함

## 버저닝
- URL path: /v1/users (권장)
- Header: Accept: application/vnd.api+json;version=1

## 인증
- Bearer token (JWT) 기본
- API Key는 서버간 통신에만
- OAuth2 flow: Authorization Code (웹), Client Credentials (서버간)

---

## MCP 연동

이 스킬은 특정 MCP에 의존하지 않음. API 설계 가이드 목적.
- API Gateway 배포 시 → `aws-serverless-eda` 또는 `api-gateway` 스킬 참조
- OpenAPI 스펙 관리 시 → GitLab MCP (gitlab-mcp)로 스펙 파일 조회/수정 가능
