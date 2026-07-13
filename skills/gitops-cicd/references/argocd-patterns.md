# ArgoCD 패턴 가이드

## App-of-Apps 설정

### 구조
```
argocd/
├── root-app.yaml              # 루트 Application (이것만 수동 배포)
├── apps/
│   ├── dev/
│   │   ├── api.yaml           # dev 환경 api Application
│   │   ├── worker.yaml
│   │   └── monitoring.yaml
│   ├── staging/
│   │   ├── api.yaml
│   │   └── worker.yaml
│   └── prod/
│       ├── api.yaml
│       └── worker.yaml
```

### Root Application
```yaml
# argocd/root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.example.com/your-group/gitops-manifest.git
    targetRevision: main
    path: argocd/apps/dev  # 환경별 변경
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 하위 Application
```yaml
# argocd/apps/dev/api.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api-dev
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # 순서 제어
spec:
  project: default
  source:
    repoURL: https://gitlab.example.com/your-group/gitops-manifest.git
    targetRevision: main
    path: overlays/dev/api
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## Sync Wave (배포 순서 제어)

```yaml
# Wave 0: Namespace, ConfigMap, Secret
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Wave 1: Database (StatefulSet)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"

# Wave 2: Application (Deployment)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"

# Wave 3: Ingress
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "3"
```

순서: 낮은 wave → 높은 wave (같은 wave는 병렬)

---

## Kustomize Overlay 구조

```
k8s-manifests/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── hpa.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── patch-replicas.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   └── patch-resources.yaml
    └── prod/
        ├── kustomization.yaml
        ├── patch-replicas.yaml
        └── patch-resources.yaml
```

### base/kustomization.yaml
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - hpa.yaml
```

### overlays/prod/kustomization.yaml
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: production
resources:
  - ../../base
patches:
  - path: patch-replicas.yaml
  - path: patch-resources.yaml
images:
  - name: api-server
    newName: 123456789.dkr.ecr.ap-northeast-2.amazonaws.com/api
    newTag: abc1234  # CI에서 업데이트
```

### overlays/prod/patch-replicas.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  replicas: 3
```

---

## 시크릿 관리

### 방법 1: Sealed Secrets
```bash
# 암호화 (클러스터 공개키로)
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
# sealed-secret.yaml은 Git에 커밋 가능 (암호화됨)
```

### 방법 2: External Secrets Operator (권장)
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-credentials  # 생성될 K8s Secret 이름
  data:
    - secretKey: password
      remoteRef:
        key: prod/db/credentials  # AWS Secrets Manager 키
        property: password
```

### 방법 3: SOPS + Age
```bash
# 암호화
sops --encrypt --age $(cat key.pub) secrets.yaml > secrets.enc.yaml

# ArgoCD에서 복호화 (sops plugin)
# argocd-repo-server에 sops 설치 필요
```

---

## 환경별 Sync 전략

| 환경 | Sync | Prune | Self-Heal | 승인 |
|------|:----:|:-----:|:---------:|:----:|
| dev | Auto | ✅ | ✅ | 불필요 |
| staging | Auto | ✅ | ✅ | 불필요 |
| prod | Manual | ✅ | ❌ | 필요 |

### Production Manual Sync
```yaml
syncPolicy:
  # automated 제거 → Manual
  syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
```

### Sync 전 검증 (PreSync Hook)
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: api-server:latest
          command: ["npm", "run", "migrate"]
      restartPolicy: Never
```

---

## 이미지 태그 업데이트 자동화

### CI에서 manifest repo 업데이트
```bash
# GitLab CI deploy job
git clone https://oauth2:$TOKEN@gitlab.example.com/your-group/gitops-manifest.git
cd cicd-eks-manifest

# kustomize 이미지 태그 변경
cd overlays/dev
kustomize edit set image api-server=$ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHORT_SHA

git add .
git commit -m "chore(dev): update api image to $CI_COMMIT_SHORT_SHA"
git push
# → ArgoCD가 자동 감지 → sync
```

### ArgoCD Image Updater (자동)
```yaml
# Application annotation
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: api=$ECR_REGISTRY/api
    argocd-image-updater.argoproj.io/api.update-strategy: latest
    argocd-image-updater.argoproj.io/api.allow-tags: regexp:^[a-f0-9]{7}$
```
