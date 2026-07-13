# Values 설계 패턴

## 구조화 원칙

### 최상위 그룹핑
```yaml
# values.yaml
replicaCount: 2

image:
  repository: 123456789.dkr.ecr.ap-northeast-2.amazonaws.com/api
  tag: ""  # Chart.appVersion 사용
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 3000

ingress:
  enabled: false
  className: alb
  annotations: {}
  hosts: []
  tls: []

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPU: 70

env: {}
envFromSecret: {}

serviceAccount:
  create: true
  name: ""
  annotations: {}

nodeSelector: {}
tolerations: []
affinity: {}
```

---

## 환경별 Override

### values-dev.yaml
```yaml
replicaCount: 1

image:
  tag: latest

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi

env:
  LOG_LEVEL: debug
  NODE_ENV: development

ingress:
  enabled: true
  hosts:
    - host: api-dev.internal.example.com
      paths:
        - path: /
          pathType: Prefix
```

### values-prod.yaml
```yaml
replicaCount: 3

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPU: 60

env:
  LOG_LEVEL: info
  NODE_ENV: production

ingress:
  enabled: true
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
  hosts:
    - host: api.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - api.example.com
      secretName: api-tls
```

### 사용법
```bash
# dev
helm upgrade --install api ./charts/api -f values-dev.yaml

# prod
helm upgrade --install api ./charts/api -f values-prod.yaml
```

---

## 시크릿 관리 패턴

### 방법 1: External Secrets (권장)
```yaml
# values.yaml에 시크릿 값 넣지 않음
externalSecrets:
  enabled: true
  secretStore: aws-secrets-manager
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: prod/api/db-url
    - secretKey: API_KEY
      remoteRef:
        key: prod/api/api-key
```

### 방법 2: Sealed Secrets
```yaml
# sealed-secret.yaml (암호화된 상태로 Git에 커밋)
sealedSecrets:
  enabled: true
  encryptedData:
    DATABASE_URL: AgBy3i4OJSWK+PiTySYZZA9rO...
```

### 방법 3: Helm secrets plugin (sops)
```bash
# 암호화된 values 파일
helm secrets upgrade api ./charts/api -f values-prod.yaml -f secrets-prod.yaml
```

---

## 설계 팁

### 1. 합리적 기본값
```yaml
# Good: 기본값으로 바로 동작 가능
replicaCount: 1
service:
  port: 80

# Bad: 필수값이 비어있어서 에러
database:
  host: ""  # 반드시 override 필요 → 에러 메시지 불친절
```

### 2. 필수값 검증 (templates에서)
```yaml
{{- if not .Values.image.repository }}
{{- fail "image.repository is required" }}
{{- end }}
```

### 3. 중첩 최소화
```yaml
# Good: 2단계 이내
service:
  port: 80

# Bad: 깊은 중첩
config:
  server:
    http:
      listen:
        port: 80  # override하기 번거로움
```

### 4. 배열보다 맵 선호 (merge 가능)
```yaml
# Good: 맵 (환경별 merge 가능)
env:
  NODE_ENV: production
  LOG_LEVEL: info

# 주의: 배열 (환경별 override 시 전체 교체됨)
extraEnv:
  - name: NODE_ENV
    value: production
```

### 5. 주석으로 문서화
```yaml
# -- Number of replicas for the deployment
replicaCount: 2

# -- Image configuration
image:
  # -- Container image repository
  repository: my-app
  # -- Image tag (defaults to Chart.appVersion)
  tag: ""
```

> `# --` 형식은 helm-docs 도구가 자동으로 README 생성 시 사용
