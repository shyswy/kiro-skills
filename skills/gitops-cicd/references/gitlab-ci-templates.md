# GitLab CI 재사용 템플릿

## Node.js 프로젝트 템플릿

```yaml
# .gitlab-ci.yml
stages:
  - install
  - lint
  - test
  - build
  - publish
  - deploy

variables:
  NODE_IMAGE: node:20-alpine
  DOCKER_IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

# --- 공통 ---
.node-cache:
  cache:
    key:
      files:
        - pnpm-lock.yaml
    paths:
      - node_modules/
      - .pnpm-store/

install:
  stage: install
  image: $NODE_IMAGE
  extends: .node-cache
  script:
    - corepack enable
    - pnpm install --frozen-lockfile
  artifacts:
    paths:
      - node_modules/
    expire_in: 1 hour

lint:
  stage: lint
  image: $NODE_IMAGE
  needs: [install]
  script:
    - pnpm lint
    - pnpm type-check

test:unit:
  stage: test
  image: $NODE_IMAGE
  needs: [install]
  script:
    - pnpm test:unit --coverage
  coverage: '/All files[^|]*\|[^|]*\s+([\d\.]+)/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml

test:integration:
  stage: test
  image: $NODE_IMAGE
  needs: [install]
  services:
    - postgres:16-alpine
    - redis:7-alpine
  variables:
    POSTGRES_DB: testdb
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
    DATABASE_URL: postgresql://test:test@postgres:5432/testdb
    REDIS_URL: redis://redis:6379
  script:
    - pnpm test:integration

build:docker:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t $DOCKER_IMAGE .
    - docker tag $DOCKER_IMAGE $CI_REGISTRY_IMAGE:latest
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

publish:ecr:
  stage: publish
  image: amazon/aws-cli:2
  script:
    - aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin $ECR_REGISTRY
    - docker push $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHORT_SHA
    - docker push $ECR_REGISTRY/$ECR_REPO:latest
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

deploy:dev:
  stage: deploy
  image: alpine:3
  script:
    - apk add --no-cache git
    - git clone https://oauth2:$MANIFEST_TOKEN@gitlab.example.com/your-group/gitops-manifest.git
    - cd cicd-eks-manifest
    - "sed -i 's|image:.*|image: $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHORT_SHA|' overlays/dev/deployment.yaml"
    - git add . && git commit -m "chore: update image to $CI_COMMIT_SHORT_SHA" && git push
  environment:
    name: development
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

deploy:prod:
  stage: deploy
  extends: .deploy-manifest
  environment:
    name: production
  when: manual
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

---

## Docker 빌드 + ECR Push (공통 include)

```yaml
# templates/docker-build.yml
.docker-build:
  image: docker:24
  services:
    - docker:24-dind
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker build
      --cache-from $CI_REGISTRY_IMAGE:latest
      --tag $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
      --tag $CI_REGISTRY_IMAGE:latest
      --build-arg BUILDKIT_INLINE_CACHE=1
      .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
    - docker push $CI_REGISTRY_IMAGE:latest

.ecr-push:
  image: amazon/aws-cli:2
  before_script:
    - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
  script:
    - docker pull $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
    - docker tag $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHORT_SHA
    - docker push $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHORT_SHA
```

### 사용법
```yaml
include:
  - local: templates/docker-build.yml

build:
  stage: build
  extends: .docker-build
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

---

## Helm 배포 템플릿

```yaml
# templates/helm-deploy.yml
.helm-deploy:
  image: alpine/helm:3.14
  before_script:
    - aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION
  script:
    - helm upgrade --install $RELEASE_NAME ./charts/$CHART_NAME
      --namespace $NAMESPACE
      --set image.tag=$CI_COMMIT_SHORT_SHA
      --set image.repository=$ECR_REGISTRY/$ECR_REPO
      --values ./charts/$CHART_NAME/values-$ENV.yaml
      --atomic
      --timeout 5m
      --wait
```

---

## Kaniko 빌드 (DinD 없이)

```yaml
build:kaniko:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:v1.21.0-debug
    entrypoint: [""]
  script:
    - /kaniko/executor
      --context $CI_PROJECT_DIR
      --dockerfile $CI_PROJECT_DIR/Dockerfile
      --destination $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHORT_SHA
      --destination $ECR_REGISTRY/$ECR_REPO:latest
      --cache=true
      --cache-repo=$ECR_REGISTRY/$ECR_REPO/cache
```

---

## 보안 스캔 통합

```yaml
security:trivy:
  stage: test
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
  allow_failure: true
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

security:secrets:
  stage: lint
  image:
    name: zricethezav/gitleaks:latest
    entrypoint: [""]
  script:
    - gitleaks detect --source . --verbose
```
