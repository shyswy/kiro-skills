# 로그 수집 파이프라인 설정

## Fluent Bit (경량, K8s 권장)

### DaemonSet 설정 (K8s)
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         5
        Log_Level     info
        Parsers_File  parsers.conf

    [INPUT]
        Name              tail
        Tag               kube.*
        Path              /var/log/containers/*.log
        Parser            cri
        DB                /var/log/flb_kube.db
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On
        Refresh_Interval  10

    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_Tag_Prefix     kube.var.log.containers.
        Merge_Log           On
        Keep_Log            Off
        K8S-Logging.Parser  On
        K8S-Logging.Exclude On

    [FILTER]
        Name    modify
        Match   kube.*
        Remove  stream
        Remove  logtag

    [OUTPUT]
        Name            es
        Match           kube.*
        Host            ${ES_HOST}
        Port            443
        TLS             On
        AWS_Auth        On
        AWS_Region      ap-northeast-2
        Index           logs-${NAMESPACE}-%Y.%m.%d
        Type            _doc
        Retry_Limit     3

  parsers.conf: |
    [PARSER]
        Name        json
        Format      json
        Time_Key    timestamp
        Time_Format %Y-%m-%dT%H:%M:%S.%LZ

    [PARSER]
        Name        cri
        Format      regex
        Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z
```

---

## Filebeat (ELK 스택)

### filebeat.yml
```yaml
filebeat.inputs:
  - type: container
    paths:
      - /var/log/containers/*.log
    processors:
      - add_kubernetes_metadata:
          host: ${NODE_NAME}
          matchers:
            - logs_path:
                logs_path: "/var/log/containers/"

filebeat.autodiscover:
  providers:
    - type: kubernetes
      node: ${NODE_NAME}
      hints.enabled: true
      hints.default_config:
        type: container
        paths:
          - /var/log/containers/*${data.kubernetes.container.id}.log

processors:
  - decode_json_fields:
      fields: ["message"]
      target: ""
      overwrite_keys: true
  - drop_fields:
      fields: ["agent", "ecs", "host.name"]

output.elasticsearch:
  hosts: ["${ES_HOST}:443"]
  protocol: "https"
  index: "logs-%{[kubernetes.namespace]}-%{+yyyy.MM.dd}"

setup.ilm.enabled: true
setup.ilm.rollover_alias: "logs"
setup.ilm.pattern: "{now/d}-000001"
```

---

## 구조화된 로깅 (애플리케이션)

### Node.js (pino)
```typescript
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  redact: ['req.headers.authorization', 'password', 'token'],
});

// 사용
logger.info({ userId: '123', action: 'login' }, 'User logged in');
logger.error({ err, orderId: '456' }, 'Payment failed');
```

### 출력 형식
```json
{
  "level": "info",
  "time": "2026-05-20T10:00:00.000Z",
  "msg": "User logged in",
  "userId": "123",
  "action": "login",
  "requestId": "req-abc-123",
  "service": "api-gateway"
}
```

### Correlation ID 전파
```typescript
// 미들웨어에서 설정
app.use((req, res, next) => {
  req.requestId = req.headers['x-request-id'] || crypto.randomUUID();
  res.setHeader('x-request-id', req.requestId);
  next();
});

// 하위 서비스 호출 시 전파
const response = await axios.get(url, {
  headers: { 'x-request-id': req.requestId }
});
```

---

## CloudWatch Logs Insights 쿼리 패턴

### 에러 로그 검색
```
fields @timestamp, @message, level, requestId
| filter level = "error"
| sort @timestamp desc
| limit 50
```

### 느린 요청 찾기
```
fields @timestamp, path, duration, statusCode
| filter duration > 2000
| sort duration desc
| limit 20
```

### 에러율 시계열
```
filter level = "error"
| stats count(*) as errors by bin(5m)
```

### 특정 사용자 추적
```
fields @timestamp, @message, level
| filter userId = "user-123"
| sort @timestamp asc
```

### 상위 에러 패턴
```
filter level = "error"
| stats count(*) as cnt by msg
| sort cnt desc
| limit 10
```

---

## 로그 레벨 동적 변경

### 환경변수 기반
```typescript
// 재시작 없이 로그 레벨 변경 (signal 기반)
process.on('SIGUSR2', () => {
  const newLevel = logger.level === 'debug' ? 'info' : 'debug';
  logger.level = newLevel;
  logger.info(`Log level changed to: ${newLevel}`);
});
```

### API 엔드포인트 기반
```typescript
app.put('/admin/log-level', (req, res) => {
  const { level } = req.body;
  if (['debug', 'info', 'warn', 'error'].includes(level)) {
    logger.level = level;
    res.json({ level });
  }
});
```

---

## 민감 정보 마스킹

```typescript
const redactPaths = [
  'password',
  'token',
  'authorization',
  'creditCard',
  '*.password',
  'req.headers.authorization',
];

// pino redact
const logger = pino({ redact: redactPaths });

// 커스텀 마스킹
function maskPII(obj: Record<string, unknown>): Record<string, unknown> {
  const masked = { ...obj };
  if (masked.email) masked.email = (masked.email as string).replace(/(.{2}).*(@.*)/, '$1***$2');
  if (masked.phone) masked.phone = '***-****-' + (masked.phone as string).slice(-4);
  return masked;
}
```
