---
name: rdb-optimization
description: |
  PostgreSQL/MySQL 쿼리 최적화, 인덱스 설계, 트랜잭션 관리, 파티셔닝, RDS Proxy 가이드.
  EXPLAIN 분석, connection pool, 대규모 데이터 처리 패턴을 다룬다.
  트리거: PostgreSQL, MySQL, query optimization, index, transaction, EXPLAIN, 파티셔닝, RDS Proxy, connection pool, 쿼리 최적화, 인덱스, 트랜잭션, 슬로우 쿼리, DB 성능, 커넥션 풀
license: MIT
---

# RDB Optimization

## EXPLAIN 분석
- EXPLAIN ANALYZE로 실제 실행 계획 확인
- 주의 지표: Seq Scan (대용량 테이블), Nested Loop (큰 결과셋), Sort (메모리 초과)
- PostgreSQL: EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
- MySQL: EXPLAIN FORMAT=JSON, EXPLAIN ANALYZE (8.0+)

## 쿼리 튜닝 판단 기준
- 단순 WHERE 느림 → 인덱스 추가 (references/index-strategy.md)
- 인덱스 있는데 느림 → 쿼리 리팩토링 (references/query-tuning.md)
- 조인 5개+ → 비정규화 또는 materialized view
- 집계 쿼리 느림 → 사전 집계 또는 CQRS
- 단일 쿼리 한계 → 캐시(Redis) 또는 검색엔진(ES) 분리
- 연결 문제 → references/connection-management.md
- 흔한 실수 → references/anti-patterns.md

## 인덱스 전략
- WHERE, JOIN, ORDER BY 컬럼에 인덱스
- 복합 인덱스: 등호 조건 → 범위 조건 → 정렬 순서
- Covering Index: SELECT 컬럼까지 포함 (Index Only Scan)
- Partial Index (PostgreSQL): WHERE 조건 포함 인덱스
- 인덱스 과다 주의: 쓰기 성능 저하, 스토리지 증가

## 트랜잭션
- 최소 범위로 유지 (lock 시간 최소화)
- READ COMMITTED 기본 (PostgreSQL)
- REPEATABLE READ: 일관된 읽기 필요 시
- Deadlock 방지: 항상 같은 순서로 리소스 접근

## 파티셔닝
- Range: 시간 기반 데이터 (로그, 이벤트)
- List: 카테고리별 분리
- Hash: 균등 분산
- PostgreSQL: PARTITION BY RANGE/LIST/HASH
- MySQL: PARTITION BY RANGE COLUMNS

## RDS Proxy
- Lambda → RDS 연결 시 필수 (connection pool 공유)
- 연결 수 제한: max_connections의 80% 이하로 proxy 설정
- IAM 인증 지원
- 장애 조치: 자동 failover (Multi-AZ)

## Connection Pool
- 애플리케이션 레벨: pgBouncer (PostgreSQL), ProxySQL (MySQL)
- pool size = (core_count * 2) + effective_spindle_count
- idle timeout 설정으로 좀비 연결 방지

## 대규모 데이터 처리
- Batch INSERT: VALUES 다중 행 (1000개 단위)
- COPY (PostgreSQL) / LOAD DATA (MySQL): 벌크 로드
- 대용량 DELETE: 배치 삭제 (LIMIT + 반복)
- 대용량 ALTER: pt-online-schema-change 또는 gh-ost

---

## MCP 연동

### 사용 MCP: aws-cloudwatch
- 상태: ✅ 연동됨 (user-scope-config.md 참조)
- 활용 시나리오:
  - RDS 메트릭: `mcp_aws_cloudwatch_get_metric_data` (namespace: AWS/RDS)
  - 주요 메트릭: CPUUtilization, FreeableMemory, ReadIOPS, WriteIOPS, DatabaseConnections
  - Slow query 로그: `mcp_aws_cloudwatch_execute_log_insights_query` (/aws/rds/...)
  - RDS Proxy 메트릭: ClientConnections, DatabaseConnections, QueryDatabaseResponseLatency
  - 알람: `mcp_aws_cloudwatch_get_active_alarms`

### 참고
- PostgreSQL 심화 패턴은 `supabase-postgres-best-practices` 스킬도 참조
- Lambda → RDS 연동 시 RDS Proxy 필수 → `aws-serverless-eda` 스킬 참조
