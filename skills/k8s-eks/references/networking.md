# EKS 네트워킹 가이드

## VPC CNI (Amazon VPC Container Network Interface)

### 동작 원리
- 각 Pod에 VPC 내 실제 IP 할당 (ENI secondary IP)
- Pod IP = VPC IP → VPC 내 다른 리소스와 직접 통신 가능
- ENI당 IP 수 제한: 인스턴스 타입별 다름

### 인스턴스별 Pod 수 제한
```
최대 Pod 수 = (ENI 수 × ENI당 IP 수) - 1

예시:
- m5.large: (3 × 10) - 1 = 29 Pods
- m5.xlarge: (4 × 15) - 1 = 59 Pods
- m5.2xlarge: (4 × 15) - 1 = 59 Pods
```

### Prefix Delegation (Pod 밀도 증가)
```yaml
# aws-node DaemonSet 환경변수
env:
  - name: ENABLE_PREFIX_DELEGATION
    value: "true"
  - name: WARM_PREFIX_TARGET
    value: "1"
# /28 prefix (16 IPs) 단위 할당 → Pod 밀도 대폭 증가
# m5.large: 최대 110 Pods
```

### Custom Networking (Pod를 별도 서브넷에)
```yaml
# ENIConfig로 Pod 서브넷 지정
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ap-northeast-2a
spec:
  subnet: subnet-0abc123  # Pod 전용 서브넷
  securityGroups:
    - sg-0def456
```
용도: 노드는 private 서브넷, Pod는 별도 서브넷 (IP 고갈 방지)

---

## Service 타입별 선택

| 타입 | 용도 | 외부 접근 |
|------|------|:---------:|
| ClusterIP | 클러스터 내부 통신 | ❌ |
| NodePort | 개발/테스트 | 노드 IP:Port |
| LoadBalancer | 외부 노출 (NLB/CLB) | ✅ |
| Ingress (ALB) | HTTP/HTTPS 라우팅 | ✅ |

### AWS Load Balancer Controller
```yaml
# ALB Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip  # Pod IP 직접 (권장)
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/healthcheck-path: /health
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 80
```

### NLB (TCP/UDP, 고성능)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: grpc-service
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internal
spec:
  type: LoadBalancer
  ports:
    - port: 443
      targetPort: 8443
      protocol: TCP
```

---

## NetworkPolicy

### 기본: 모든 트래픽 차단 (Zero Trust)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: production
spec:
  podSelector: {}  # 모든 Pod
  policyTypes:
    - Ingress
    - Egress
```

### 특정 서비스 간 통신만 허용
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: postgres
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 5432
```

### DNS 허용 (필수)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
spec:
  podSelector: {}
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

> ⚠️ EKS 기본 VPC CNI는 NetworkPolicy 미지원. Calico 또는 VPC CNI v1.14+ (네트워크 정책 지원) 필요.

---

## CoreDNS 최적화

### ndots 설정 (DNS 쿼리 최소화)
```yaml
# Pod spec에 dnsConfig 추가
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "2"  # 기본 5 → 2로 줄이면 외부 도메인 쿼리 빨라짐
```

### NodeLocal DNSCache
```
Pod → NodeLocal DNS (127.0.0.53) → CoreDNS → Route53
```
- 노드 로컬 캐시로 CoreDNS 부하 감소
- DNS 응답 시간 단축 (네트워크 홉 감소)

---

## Security Group for Pods

```yaml
# Pod에 개별 Security Group 할당 (VPC CNI)
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: db-access-policy
spec:
  podSelector:
    matchLabels:
      app: api-server
  securityGroups:
    groupIds:
      - sg-0abc123  # RDS 접근 허용 SG
```

용도: Pod별로 RDS, ElastiCache 등 VPC 리소스 접근 제어

---

## Private Cluster 구성

```
Internet → ALB (public subnet) → Pod (private subnet) → RDS/MSK (private)
                                                       → NAT GW → Internet (outbound)
```

### 필수 VPC Endpoints (NAT 비용 절감)
- `com.amazonaws.{region}.s3` — ECR 이미지 레이어
- `com.amazonaws.{region}.ecr.api` — ECR API
- `com.amazonaws.{region}.ecr.dkr` — ECR Docker
- `com.amazonaws.{region}.sts` — IRSA
- `com.amazonaws.{region}.logs` — CloudWatch Logs
- `com.amazonaws.{region}.elasticloadbalancing` — ALB Controller
