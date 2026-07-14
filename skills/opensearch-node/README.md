# opensearch-node

> OpenSearch Node.js 클라이언트 TypeScript 구현 패턴

## When to Use
- OpenSearch 클라이언트 설정 (SigV4, Basic Auth)
- 인덱스 생성/관리 코드 작성
- Bulk indexing, 검색 쿼리 구현
- Testcontainers로 OpenSearch 테스트

## What It Covers
- @opensearch-project/opensearch 클라이언트 TypeScript 패턴
- AWS SigV4 인증 vs Basic Auth 자동 분기
- 인덱스 template/lifecycle 관리
- Bulk indexing (배치, retry on 429)
- Search query builder (bool, range, pagination)
- 에러 핸들링 (ResponseError 분류)
- 싱글턴 팩토리 + Health check
- Testcontainers 통합 테스트

## Attribution
- Tier: 3 (직접 작성)
