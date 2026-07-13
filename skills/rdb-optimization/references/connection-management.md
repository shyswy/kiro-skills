# Connection 관리

## Connection Pool 사이징

### 공식
```
pool_size = (core_count * 2) + effective_spindle_count
```
- 일반적으로 CPU 코어 수의 2~4배
- SSD 환경: spindle_count = 1로 간주
- 예: 4 core → pool_size = 9~17

### 과도한 연결의 문제
- 각 연결 = ~10MB 메모리 (PostgreSQL)
- 컨텍스트 스위칭 오버헤드
- max_connections 초과 시 연결 거부
- 권장: 애플리케이션 pool < DB max_connections의 80%

---

## pgBouncer (PostgreSQL)

### 모드
| 모드 | 설명 | 용도 |
|------|------|------|
| session | 클라이언트 연결 동안 서버 연결 점유 | 기본, prepared statement 사용 시 |
| transaction | 트랜잭션 동안만 서버 연결 점유 | 대부분의 웹 앱 (권장) |
| statement | 쿼리 단위로 서버 연결 할당 | autocommit만 사용하는 경우 |

### 설정 예시 (pgbouncer.ini)
```ini
[databases]
mydb = host=db-host port=5432 dbname=mydb

[pgbouncer]
listen_port = 6432
pool_mode = transaction
max_client_conn = 1000      # 클라이언트 최대 연결
default_pool_size = 20       # DB당 서버 연결 수
min_pool_size = 5            # 최소 유지 연결
reserve_pool_size = 5        # 대기열 초과 시 추가 연결
reserve_pool_timeout = 3     # 추가 연결 대기 시간 (초)
server_idle_timeout = 600    # 유휴 서버 연결 해제 (초)
```

### 주의사항
- transaction 모드에서 prepared statement 사용 불가 (세션 간 공유 안 됨)
- SET 명령어 세션 유지 안 됨 → 쿼리 내에서 처리
- LISTEN/NOTIFY 사용 불가 (session 모드 필요)

---

## ProxySQL (MySQL)

### 설정 예시
```sql
-- 백엔드 서버 등록
INSERT INTO mysql_servers (hostgroup_id, hostname, port, max_connections)
VALUES (0, 'writer.rds.amazonaws.com', 3306, 100);
INSERT INTO mysql_servers (hostgroup_id, hostname, port, max_connections)
VALUES (1, 'reader.rds.amazonaws.com', 3306, 200);

-- 쿼리 라우팅 (읽기/쓰기 분리)
INSERT INTO mysql_query_rules (rule_id, match_pattern, destination_hostgroup)
VALUES (1, '^SELECT.*FOR UPDATE', 0);  -- writer
INSERT INTO mysql_query_rules (rule_id, match_pattern, destination_hostgroup)
VALUES (2, '^SELECT', 1);              -- reader

LOAD MYSQL SERVERS TO RUNTIME;
LOAD MYSQL QUERY RULES TO RUNTIME;
```

---

## AWS RDS Proxy

### 아키텍처
```
Lambda/ECS → RDS Proxy → RDS (Writer/Reader)
```

### 핵심 설정
- **Max connections percent**: RDS max_connections의 몇 %까지 사용 (기본 100)
- **Idle client timeout**: 유휴 클라이언트 연결 해제 시간
- **Connection borrow timeout**: 연결 대기 최대 시간 (초과 시 에러)

### Lambda + RDS Proxy 패턴
```typescript
// Lambda에서 RDS Proxy 사용 (IAM 인증)
import { RDSDataClient } from '@aws-sdk/client-rds-data';

// 또는 직접 연결 (Proxy endpoint 사용)
const pool = new Pool({
  host: 'my-proxy.proxy-xxx.ap-northeast-2.rds.amazonaws.com',
  port: 5432,
  database: 'mydb',
  user: 'admin',
  ssl: { rejectUnauthorized: true },
  max: 1,  // Lambda는 1로 설정 (Proxy가 풀링)
});
```

### RDS Proxy vs pgBouncer 비교
| 항목 | RDS Proxy | pgBouncer |
|------|-----------|-----------|
| 관리 | AWS managed | 자체 운영 |
| 비용 | vCPU 시간당 과금 | 무료 (인프라 비용만) |
| 장애 조치 | 자동 failover | 수동 설정 필요 |
| IAM 인증 | ✅ | ❌ |
| Lambda 통합 | 최적화됨 | 별도 설정 필요 |
| 세밀한 제어 | 제한적 | 상세 설정 가능 |

---

## 연결 누수 감지

### PostgreSQL
```sql
-- 현재 연결 상태 확인
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

-- idle 연결이 오래된 것 찾기
SELECT pid, now() - state_change as idle_duration, query
FROM pg_stat_activity
WHERE state = 'idle'
ORDER BY idle_duration DESC;

-- 강제 종료 (최후의 수단)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle' AND now() - state_change > interval '1 hour';
```

### MySQL
```sql
-- 현재 연결 확인
SHOW PROCESSLIST;

-- Sleep 연결 찾기
SELECT * FROM information_schema.PROCESSLIST
WHERE COMMAND = 'Sleep' AND TIME > 300;

-- 강제 종료
KILL CONNECTION <id>;
```

### 애플리케이션 레벨 방지
- 반드시 finally/using 블록에서 연결 반환
- ORM의 connection release 설정 확인
- idle timeout 설정 (pool에서 자동 해제)
- leak detection: HikariCP의 leakDetectionThreshold
