# EKS 트러블슈팅 가이드

## Pod 상태별 대응

### CrashLoopBackOff
```bash
# 1. 로그 확인
kubectl logs <pod> --previous  # 이전 크래시 로그

# 2. 이벤트 확인
kubectl describe pod <pod>

# 3. 일반적 원인
```
| 원인 | 증상 | 해결 |
|------|------|------|
| 앱 에러 (uncaught exception) | 로그에 에러 스택 | 코드 수정 |
| 설정 누락 (env, configmap) | "config not found" | ConfigMap/Secret 확인 |
| 포트 충돌 | "address already in use" | containerPort 확인 |
| 헬스체크 실패 | liveness probe failed | probe 설정 조정 |
| 의존성 미준비 | "connection refused" | initContainer 또는 readiness 대기 |

### OOMKilled
```bash
# 확인
kubectl describe pod <pod> | grep -A5 "Last State"
# Reason: OOMKilled

# 대응
```
1. `kubectl top pod <pod>` — 실제 메모리 사용량 확인
2. memory limits 증가 (임시)
3. 메모리 누수 조사:
   - Node.js: `--max-old-space-size` 설정 확인
   - Java: `-XX:MaxRAMPercentage=75` (limits의 75%)
   - 힙 덤프 분석

### ImagePullBackOff
```bash
kubectl describe pod <pod> | grep -A3 "Events"
```
| 원인 | 해결 |
|------|------|
| 이미지 없음 | 이미지 태그/이름 확인 |
| ECR 인증 실패 | IRSA 설정 확인, `ecr:GetAuthorizationToken` 권한 |
| Private registry | imagePullSecrets 설정 |
| Rate limit (DockerHub) | ECR로 미러링 |

### Pending (스케줄링 실패)
```bash
kubectl describe pod <pod> | grep -A10 "Events"
# "0/3 nodes are available: insufficient cpu/memory"
```
| 원인 | 해결 |
|------|------|
| 리소스 부족 | 노드 추가 (Karpenter/CA) 또는 requests 줄이기 |
| nodeSelector 불일치 | 라벨 확인 |
| Taint/Toleration | toleration 추가 |
| PVC 바인딩 실패 | StorageClass, AZ 확인 |
| Affinity 불만족 | affinity 규칙 완화 |

---

## 네트워크 문제

### DNS 해결 실패
```bash
# Pod 내에서 DNS 테스트
kubectl exec -it <pod> -- nslookup kubernetes.default
kubectl exec -it <pod> -- nslookup external-service.com

# CoreDNS 상태 확인
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### Service 연결 불가
```bash
# 1. Service 엔드포인트 확인
kubectl get endpoints <service-name>
# endpoints가 비어있으면 → selector 불일치

# 2. Pod에서 직접 연결 테스트
kubectl exec -it <pod> -- curl http://<service-name>:<port>/health

# 3. NetworkPolicy 확인
kubectl get networkpolicy -n <namespace>
```

### 외부 통신 불가 (Egress)
```bash
# NAT Gateway 확인
# Pod → NAT GW → Internet

# 1. Pod에서 외부 연결 테스트
kubectl exec -it <pod> -- curl -v https://httpbin.org/ip

# 2. 확인 사항:
# - 서브넷 라우팅 테이블에 NAT GW 경로 있는지
# - Security Group outbound 규칙
# - NetworkPolicy egress 허용 여부
```

---

## 노드 문제

### NotReady 상태
```bash
kubectl describe node <node-name>
# Conditions 섹션 확인: MemoryPressure, DiskPressure, PIDPressure
```
| Condition | 원인 | 대응 |
|-----------|------|------|
| MemoryPressure | 노드 메모리 부족 | Pod eviction 발생, 노드 스케일 |
| DiskPressure | 디스크 부족 | 로그/이미지 정리, EBS 확장 |
| PIDPressure | 프로세스 과다 | 좀비 프로세스 정리 |
| NetworkUnavailable | CNI 문제 | aws-node DaemonSet 확인 |

### 노드 디스크 부족
```bash
# 미사용 이미지 정리
crictl rmi --prune

# 노드 접속 후 확인
df -h /var/lib/containerd
du -sh /var/log/pods/*
```

---

## HPA 문제

### HPA가 스케일하지 않음
```bash
kubectl describe hpa <hpa-name>
# Conditions 확인

# metrics-server 동작 확인
kubectl top pods
kubectl get apiservice v1beta1.metrics.k8s.io
```
| 원인 | 해결 |
|------|------|
| metrics-server 미설치 | metrics-server 배포 |
| 메트릭 수집 안 됨 | Pod에 resource requests 설정 필수 |
| minReplicas = maxReplicas | 범위 확인 |
| 쿨다운 기간 | stabilizationWindowSeconds 확인 |

---

## IRSA (IAM) 문제

### Pod에서 AWS API 호출 실패
```bash
# 1. ServiceAccount annotation 확인
kubectl get sa <sa-name> -o yaml
# annotations: eks.amazonaws.com/role-arn: arn:aws:iam::...

# 2. Pod 내 토큰 확인
kubectl exec -it <pod> -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token

# 3. IAM Role Trust Policy 확인
# Principal: arn:aws:iam::{account}:oidc-provider/oidc.eks.{region}.amazonaws.com/id/{id}
# Condition: sub = system:serviceaccount:{namespace}:{sa-name}
```

### 체크리스트
- [ ] OIDC Provider가 클러스터에 연결되어 있는가?
- [ ] IAM Role의 Trust Policy에 올바른 SA가 지정되어 있는가?
- [ ] ServiceAccount에 role-arn annotation이 있는가?
- [ ] Pod가 해당 ServiceAccount를 사용하는가?
- [ ] IAM Policy에 필요한 권한이 있는가?

---

## 유용한 디버깅 명령어

```bash
# Pod 상태 전체 요약
kubectl get pods -A --field-selector=status.phase!=Running

# 최근 이벤트 (문제 발생 시 첫 확인)
kubectl get events --sort-by='.lastTimestamp' -n <namespace> | tail -20

# 리소스 사용량 (top)
kubectl top nodes
kubectl top pods -n <namespace> --sort-by=memory

# Pod 내부 접속 (디버깅)
kubectl exec -it <pod> -- /bin/sh

# 임시 디버그 Pod (네트워크 테스트)
kubectl run debug --rm -it --image=nicolaka/netshoot -- /bin/bash

# 로그 스트리밍 (여러 Pod)
kubectl logs -f -l app=api-server --all-containers --max-log-requests=10

# Pod 강제 삭제 (Terminating 상태 stuck)
kubectl delete pod <pod> --grace-period=0 --force
```
