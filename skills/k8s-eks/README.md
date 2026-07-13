# k8s-eks

> Kubernetes / AWS EKS 컨테이너 오케스트레이션 가이드 — Pod 설계, IRSA, Karpenter, node group 전략

## When to Use

- Kubernetes, EKS, pod, deployment, service, ingress
- Karpenter, IRSA, namespace
- 쿠버네티스, 컨테이너 오케스트레이션, 클러스터, 스케일링, HPA

## What It Covers

- Pod 설계 (sidecar, init container, resource requests/limits)
- 리소스 관리 및 QoS 클래스
- IRSA (IAM Roles for Service Accounts)
- Karpenter (노드 자동 프로비저닝)
- EKS Add-ons (CoreDNS, kube-proxy, VPC CNI, EBS CSI)
- Node Group 전략 (managed vs self-managed)
- HPA/VPA/KEDA 오토스케일링
- Ingress 패턴 (ALB Ingress Controller)

## References

- `references/` — EKS 클러스터 설정 상세 가이드

## Attribution

- Custom skill (Tier 2, community fork + EKS 확장)
