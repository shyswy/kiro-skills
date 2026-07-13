# 롤백 절차 가이드

## 롤백 판단 기준

| 상황 | 롤백 여부 | 이유 |
|------|:---------:|------|
| 배포 후 에러율 5%+ 증가 | ✅ 즉시 | 사용자 영향 |
| 배포 후 레이턴시 P99 2배+ | ✅ 즉시 | 성능 저하 |
| 배포 후 특정 기능 장애 | ⚠️ 판단 | 영향 범위에 따라 |
| 배포 후 로그에 새 에러 (영향 없음) | ❌ | 핫픽스로 대응 |
| 배포 실패 (Pod 미기동) | 자동 | --atomic 옵션 |

---

## ArgoCD 롤백

### 방법 1: History에서 이전 Revision 선택
```bash
# 히스토리 확인
argocd app history <app-name>

# 특정 revision으로 롤백
argocd app rollback <app-name> <revision-number>
```

### 방법 2: Git Revert (권장 — GitOps 원칙 유지)
```bash
# manifest repo에서 이전 커밋으로 revert
cd cicd-eks-manifest
git revert HEAD  # 마지막 커밋 되돌리기
git push

# ArgoCD가 자동 감지 → sync → 이전 상태로 복원
```

### 방법 3: 이미지 태그 수동 변경
```bash
# kustomization.yaml에서 이전 태그로 변경
cd overlays/prod
kustomize edit set image api-server=$ECR_REGISTRY/api:previous-sha

git add . && git commit -m "rollback: revert api to previous-sha" && git push
```

### ArgoCD UI에서 롤백
1. Applications → 해당 앱 선택
2. History and Rollback 탭
3. 이전 revision 선택 → Rollback 클릭
4. ⚠️ 이 방법은 Git과 불일치 발생 → 이후 Git도 맞춰야 함

---

## Helm 롤백

```bash
# 릴리즈 히스토리 확인
helm history <release-name> -n <namespace>

# 이전 revision으로 롤백
helm rollback <release-name> <revision> -n <namespace>

# 롤백 확인
helm status <release-name> -n <namespace>
```

### Helm + ArgoCD 환경
- ArgoCD가 Helm을 관리하는 경우: Git revert가 정석
- ArgoCD 없이 Helm 직접 사용: `helm rollback` 사용

---

## kubectl 직접 롤백 (긴급)

```bash
# Deployment 롤백 (이전 ReplicaSet으로)
kubectl rollout undo deployment/<name> -n <namespace>

# 특정 revision으로
kubectl rollout undo deployment/<name> --to-revision=3

# 롤백 상태 확인
kubectl rollout status deployment/<name>

# 히스토리 확인
kubectl rollout history deployment/<name>
```

> ⚠️ kubectl 직접 롤백은 GitOps와 불일치 발생. 긴급 시에만 사용하고, 이후 Git manifest도 맞춰야 함.

---

## 롤백 후 검증 체크리스트

### 즉시 확인 (1분 내)
- [ ] Pod 상태: `kubectl get pods` — Running 확인
- [ ] 에러율: 이전 수준으로 복귀 확인
- [ ] 레이턴시: P99 정상 범위 확인
- [ ] 로그: 새로운 에러 없음 확인

### 5분 후 확인
- [ ] HPA: 정상 스케일링 동작
- [ ] 외부 연동: 다른 서비스와 통신 정상
- [ ] 데이터: DB 마이그레이션 호환성 (forward-compatible 확인)

### 30분 후 확인
- [ ] 메트릭 안정화: 에러율/레이턴시 추이
- [ ] 알람: 추가 알람 없음
- [ ] 사용자 리포트: CS 이슈 없음

---

## 롤백 불가 상황 대응

### DB 마이그레이션이 포함된 배포
```
문제: 새 스키마로 마이그레이션 완료 → 이전 코드가 새 스키마와 호환 안 됨

예방:
1. Expand-Contract 패턴:
   - Phase 1: 새 컬럼 추가 (기존 코드 호환)
   - Phase 2: 새 코드 배포 (새 컬럼 사용)
   - Phase 3: 구 컬럼 삭제 (다음 배포)

2. 항상 backward-compatible migration:
   - 컬럼 추가: OK (기존 코드 무시)
   - 컬럼 삭제: 위험 (이전 코드가 참조)
   - 컬럼 이름 변경: 위험 (alias 사용)
```

### 데이터 변환이 포함된 배포
```
문제: 배치 작업으로 데이터 변환 완료 → 롤백하면 데이터 불일치

대응:
1. 변환 전 스냅샷 보관
2. 역변환 스크립트 준비
3. 또는: 새 코드가 양쪽 포맷 모두 처리하도록 설계
```

---

## Canary 배포 + 자동 롤백 (Argo Rollouts)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api-server
spec:
  replicas: 5
  strategy:
    canary:
      steps:
        - setWeight: 10        # 10% 트래픽
        - pause: { duration: 5m }
        - analysis:
            templates:
              - templateName: error-rate-check
        - setWeight: 50        # 50% 트래픽
        - pause: { duration: 10m }
        - analysis:
            templates:
              - templateName: error-rate-check
      # 분석 실패 시 자동 롤백
      abortScaleDownDelaySeconds: 30

---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: error-rate-check
spec:
  metrics:
    - name: error-rate
      interval: 1m
      successCondition: result[0] < 0.05  # 에러율 5% 미만
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            sum(rate(http_requests_total{status=~"5..",app="api-server"}[5m]))
            / sum(rate(http_requests_total{app="api-server"}[5m]))
```

자동 롤백 조건: AnalysisRun 실패 → 이전 stable 버전으로 자동 복귀
