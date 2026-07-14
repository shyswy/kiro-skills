# pg-raw-query-patterns

> Node.js pg 라이브러리 PostgreSQL raw query 패턴

## When to Use
- pg Pool 설정 및 관리
- Parameterized query 작성
- Transaction 처리
- Bulk insert/upsert
- Repository 패턴 (ORM 없이)

## What It Covers
- Pool 설정 (max, timeout, search_path)
- SQL Injection 방지 (parameterized query)
- Repository 패턴 (snake_case → camelCase 매핑)
- Transaction wrapper
- Bulk insert/upsert (VALUES list 생성)
- Pagination (offset, cursor)
- Graceful shutdown (pool.end())

## Attribution
- Tier: 3 (직접 작성)
