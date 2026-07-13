---
name: k8s-eks
description: |
  Kubernetes / AWS EKS 컨테이너 오케스트레이션 가이드. Pod 설계, 리소스 관리,
  IRSA, Karpenter, add-ons, node group 전략을 다룬다.
  트리거: Kubernetes, EKS, pod, deployment, service, ingress, namespace, Karpenter, IRSA, 쿠버네티스, 컨테이너 오케스트레이션, 노드, 클러스터, 스케일링, HPA, 파드
license: MIT
---

# Kubernetes / AWS EKS Patterns

## Pod 설계
- 1 container = 1 process 원칙
- Sidecar: 로깅, 프록시, 시크릿 주입
- Init Container: 의존성 대기, 설정 초기화
- Resource requests/limits 필수 (OOM 방지)

## 리소스 관리
- requests: 스케줄링 기준 (보장량)
- limits: 최대 사용량 (초과 시 throttle/OOM kill)
- CPU: requests = limits의 50~100%
- Memory: requests ≈ limits (OOM 방지)
- LimitRange, ResourceQuota로 namespace별 제한

## Probe 설계
- livenessProbe: 프로세스 정상 여부 (실패 → 재시작)
- readinessProbe: 트래픽 수신 가능 여부 (실패 → 서비스에서 제외)
- startupProbe: 초기화 시간이 긴 앱 (실패 → 재시작, 성공 후 liveness 시작)

## IRSA (IAM Roles for Service Accounts)
- Pod에 AWS IAM 역할 부여 (node role 공유 X)
- ServiceAccount에 annotation으로 IAM role ARN 지정
- 최소 권한 원칙: Pod별 필요한 권한만

## Karpenter (노드 오토스케일링)
- NodePool: 인스턴스 타입, AZ, 용량 타입 정의
- Consolidation: 비효율 노드 자동 정리
- Spot + On-Demand 혼합 전략
- Disruption budget: 동시 축소 제한

## EKS Add-ons
- CoreDNS: 클러스터 내 DNS
- kube-proxy: 서비스 네트워킹
- VPC CNI: Pod 네트워킹 (ENI 기반)
- EBS CSI Driver: 영구 볼륨
- AWS Load Balancer Controller: ALB/NLB 자동 생성

## Namespace 전략
- 환경별: dev, staging, prod (클러스터 분리 권장)
- 팀/서비스별: team-a, payment, notification
- 시스템: kube-system, monitoring, ingress

## 배포 전략
- Rolling Update: maxSurge=25%, maxUnavailable=25%
- PDB (PodDisruptionBudget): 최소 가용 Pod 보장
- HPA: CPU/메모리 기반 수평 확장
- KEDA: 이벤트 기반 확장 (Kafka lag, SQS depth 등)

## 스케일링 판단 기준
- CPU/Memory 기반 → HPA (가장 일반적)
- 이벤트 기반 (Kafka lag, SQS depth) → KEDA
- 노드 레벨 확장 → Karpenter (Pod pending 시 자동)
- 리소스 사이징 → references/resource-sizing.md
- 네트워킹 설계 → references/networking.md
- 장애 대응 → references/troubleshooting.md

---

## MCP 연동

### 사용 MCP: aws-cloudwatch
- 상태: ✅ 연동됨 (user-scope-config.md 참조)
- 활용 시나리오:
  - EKS 클러스터 메트릭: `mcp_aws_cloudwatch_get_metric_data` (namespace: AWS/EKS, ContainerInsights)
  - 주요 메트릭: pod_cpu_utilization, pod_memory_utilization, node_cpu_utilization
  - 컨테이너 로그: `mcp_aws_cloudwatch_execute_log_insights_query` (/aws/eks/{cluster}/containers)
  - 알람: `mcp_aws_cloudwatch_get_active_alarms` (Pod restart, OOM 등)

### 참고
- EKS 직접 관리 (kubectl 명령)는 MCP 미지원 → kubectl CLI 사용
- Helm 배포 시 → `helm-charts` 스킬 참조
- ArgoCD 연동 시 → `gitops-cicd` 스킬 참조
- CDK로 EKS 정의 시 → `aws-cdk-development` 스킬 참조
