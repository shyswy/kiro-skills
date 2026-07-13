---
name: elasticsearch-opensearch
description: |
  Elasticsearch / AWS OpenSearch 검색엔진 가이드. 인덱스 설계, 매핑, 쿼리 튜닝,
  datastream, ILM, shard 전략, 한국어 분석기를 다룬다.
  트리거: Elasticsearch, OpenSearch, 인덱스, 매핑, datastream, ILM, shard, 쿼리 튜닝, 검색엔진, 검색, 풀텍스트, 집계, aggregation, 분석기, 색인, 검색 최적화
license: MIT
---

# Elasticsearch / OpenSearch Patterns

## 인덱스 설계
- 시계열 데이터: Data Stream (자동 rollover)
- 정적 데이터: 일반 인덱스 + alias
- 인덱스 네이밍: logs-{service}-{date}, products-v1

## 매핑
- Dynamic mapping 비활성화 (운영 환경)
- keyword vs text: 정확 매칭 → keyword, 전문 검색 → text
- nested vs object: 배열 내 객체 독립 쿼리 필요 → nested
- date 포맷 명시: "strict_date_optional_time||epoch_millis"
- copy_to: 여러 필드를 하나로 합쳐 검색 (full_text 필드)
- enabled: false — 저장만 하고 검색 불필요한 필드

## Shard 전략
- 1 shard = 10~50GB 권장
- Primary shard 수: 인덱스 생성 후 변경 불가 (reindex 필요)
- Replica: 가용성 + 읽기 분산 (최소 1)
- 과도한 shard 수 주의: 클러스터 오버헤드
- Shard allocation awareness: AZ별 균등 분배

## 쿼리 튜닝
- filter context 활용 (캐시됨, 스코어링 없음)
- bool query: must(스코어링) + filter(필터링) 조합
- 페이지네이션: search_after (deep pagination 시)
- 집계: terms, date_histogram, nested aggs
- profile API: 쿼리 병목 분석
- request_cache: 반복 집계 쿼리 캐싱

## Reindex 전략
- 매핑 변경 시: 새 인덱스 생성 → reindex → alias 스왑
- Zero-downtime: alias를 활용한 blue-green 인덱스 전환
- _reindex API: source/dest 지정, script로 변환 가능
- 대용량: slices=auto로 병렬 reindex
- Remote reindex: 클러스터 간 데이터 이동

## Alias 패턴
- 읽기 alias: products-read → products-v2 (버전 전환 시 변경)
- 쓰기 alias: products-write → 현재 활성 인덱스
- Rollover alias: Data Stream의 기본 동작
- Filter alias: 특정 조건의 뷰 (예: status=active만)

## ILM (Index Lifecycle Management)
- Hot → Warm → Cold → Delete
- Hot: 최신 데이터, SSD, 쓰기/읽기
- Warm: 읽기 전용, force merge (세그먼트 최적화)
- Cold: 아카이브, 저비용 스토리지
- Rollover 조건: max_size, max_age, max_docs

## 한국어 분석기
- nori 분석기 (OpenSearch/ES 기본 제공)
- 사용자 사전: userdict_ko.txt (복합명사 분리)
- decompound_mode: mixed (원형 + 분리형 모두 인덱싱)
- synonym filter: 동의어 처리
- nori_readingform: 한자 → 한글 변환

## Cross-Cluster Search
- 여러 클러스터의 인덱스를 단일 쿼리로 검색
- 설정: cluster.remote.{name}.seeds
- 쿼리: {cluster_name}:{index_pattern}
- 용도: 환경 분리된 클러스터 간 통합 검색

## AWS OpenSearch 특화
- UltraWarm: 저비용 warm 노드 (S3 기반)
- 서버리스: 소규모/간헐적 워크로드
- Fine-grained access control: IAM + 내부 DB
- 스냅샷: S3 자동 백업
- OpenSearch Dashboards: Kibana 대체 (시각화, 알림)
- Ingestion Pipeline: 데이터 변환 (grok, date, rename 등)

---

## MCP 연동

### 사용 MCP: aws-cloudwatch
- 상태: ✅ 연동됨 (user-scope-config.md 참조)
- 활용 시나리오:
  - 클러스터 상태 모니터링: `mcp_aws_cloudwatch_get_metric_data` (namespace: AWS/ES)
  - 주요 메트릭: ClusterStatus.red, FreeStorageSpace, JVMMemoryPressure, SearchLatency
  - 알람 확인: `mcp_aws_cloudwatch_get_active_alarms`
  - 로그 분석: OpenSearch slow log → CloudWatch Logs → `mcp_aws_cloudwatch_execute_log_insights_query`

### 참고
- aws-opensearch MCP (awslabs.amazon-opensearch-mcp-server)도 설치되어 있으나 현재 disabled
- 인덱스 직접 관리(매핑 생성, 쿼리 실행 등)가 필요하면 aws-opensearch MCP 활성화 권장
