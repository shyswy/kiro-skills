# AWS Networking — 의사결정 빠른 참조

> Sources:
>   - AWS VPC Documentation: https://docs.aws.amazon.com/vpc/latest/userguide/
>   - AWS Well-Architected Framework (DDoS Resiliency BP5)
>   - Content was rephrased for compliance with licensing restrictions.

---

## 트래픽 흐름과 필터링 순서

```
인터넷
  │
  ▼
[Internet Gateway / NAT Gateway]
  │
  ▼
[Route Table]           ← "이 패킷을 어디로 보낼까" (서브넷 단위)
  │
  ▼
[Network ACL (NACL)]    ← "이 서브넷에 들어오는/나가는 패킷을 허용할까" (Stateless)
  │
  ▼
[Security Group]        ← "이 인스턴스에 도달하는 패킷을 허용할까" (Stateful)
  │
  ▼
[EC2 / Lambda / ECS]
```

---

## Security Group vs NACL — 핵심 차이

| 구분 | Security Group | NACL |
|------|---------------|------|
| 적용 레벨 | **인스턴스 (ENI)** | **서브넷** |
| Stateful / Stateless | **Stateful** — 인바운드 허용하면 아웃바운드 응답 자동 허용 | **Stateless** — 인바운드/아웃바운드 각각 규칙 필요 |
| 규칙 유형 | **Allow만 가능** (Deny 없음) | **Allow + Deny** 가능 |
| 규칙 평가 | 모든 규칙 평가 → 하나라도 허용하면 통과 | **번호 순서대로** 평가, 첫 매칭 적용 (나머지 무시) |
| 기본 동작 | 같은 SG 내 통신 허용, 아웃바운드 전체 허용 | 커스텀 NACL: 전체 거부가 기본 |
| 변경 반영 | 즉시 (인스턴스 재시작 불필요) | 즉시 |

### 판단 가이드

```
Q: 어디서 제어해야 하나?

"특정 인스턴스에 대한 접근 제어" → Security Group
"서브넷 전체에 대한 차단/허용 정책" → NACL
"특정 IP 대역을 명시적으로 차단" → NACL (SG는 Deny 불가)
"같은 서브넷 내 인스턴스 간 격리" → Security Group
```

### NACL에서 자주 빠뜨리는 것: Ephemeral Ports

NACL은 **Stateless**라서, 아웃바운드 요청의 응답이 돌아올 때도 인바운드 규칙이 필요.
응답은 **ephemeral port**(1024~65535)로 돌아오므로:

```
인바운드 규칙:
  Rule 100: Allow TCP 443 from 0.0.0.0/0    ← HTTPS 요청 수신
  Rule 200: Allow TCP 1024-65535 from 0.0.0.0/0  ← 아웃바운드 요청의 응답 수신 (이거 빼면 timeout)
```

---

## VPC 연결 옵션 — 선택 가이드

### 인터넷 접근

| 시나리오 | 솔루션 | 비용 |
|---------|--------|------|
| Public 서브넷 → 인터넷 | Internet Gateway (IGW) | 무료 (데이터 전송료만) |
| Private 서브넷 → 인터넷 (아웃바운드만) | **NAT Gateway** | ~$32/월 + 데이터 처리 $0.045/GB |
| Lambda (VPC 내) → 인터넷 | NAT Gateway 필수 | 위와 동일 |

> ⚠️ **가장 흔한 실수:** Lambda를 VPC에 넣고 NAT Gateway 없이 외부 API 호출 → timeout

### AWS 서비스 접근 (인터넷 경유 안 하고)

| 시나리오 | 솔루션 | 대상 서비스 |
|---------|--------|-----------|
| S3, DynamoDB | **Gateway Endpoint** (무료) | S3, DynamoDB만 |
| 그 외 AWS 서비스 | **Interface Endpoint (PrivateLink)** | SQS, SNS, CloudWatch, Secrets Manager 등 |

> Gateway Endpoint는 **무료**, Interface Endpoint는 $7.2/월 + 데이터 처리비

### VPC 간 연결

| 시나리오 | 솔루션 | 특징 |
|---------|--------|------|
| VPC 2개 직접 연결 | **VPC Peering** | 단순, 저렴, 전이적 라우팅 불가 |
| VPC 3개 이상 허브형 | **Transit Gateway** | 중앙 집중 라우팅, 비용 높음 |
| 온프레미스 ↔ VPC | **Site-to-Site VPN** | 암호화, 인터넷 경유 |
| 온프레미스 ↔ VPC (전용선) | **Direct Connect** | 전용 물리 회선, 저지연, 고비용 |

---

## Lambda 네트워크 구성 판단

```
Q: Lambda를 VPC에 넣어야 하나?

RDS/ElastiCache 등 VPC 내 리소스 접근 필요?
├── Yes → VPC에 넣기 (Private Subnet)
│   ├── 외부 인터넷 호출도 필요? → NAT Gateway 추가
│   └── AWS 서비스만 호출? → VPC Endpoint로 해결 (NAT 불필요)
│
└── No (DynamoDB, S3, 외부 API만 호출)
    └── VPC에 넣지 마 → 기본이 인터넷 접근 가능, 설정 간단
```

### Lambda VPC 구성 시 필수 체크리스트

```
□ Private Subnet에 배치 (Public Subnet에 넣어도 인터넷 안 됨 — IGW가 ENI에 직접 연결 안 되니까)
□ NAT Gateway를 Public Subnet에 생성
□ Private Subnet의 Route Table: 0.0.0.0/0 → NAT Gateway
□ Security Group Outbound: 대상 포트 (443 등) 허용
□ Lambda 실행 역할에 ec2:CreateNetworkInterface 등 VPC 관련 권한
```

---

## 흔한 네트워크 문제 & AWS 원인

| 증상 | AWS 원인 가능성 |
|------|----------------|
| Lambda에서 외부 API timeout | VPC 내인데 NAT 없음, SG Outbound 차단 |
| ECS에서 ECR pull 실패 | Private Subnet + VPC Endpoint 없음 (또는 NAT 없음) |
| RDS 연결 timeout | SG 인바운드에 Lambda의 SG 미등록, 서브넷 NACL |
| ALB에서 502 Bad Gateway | 타겟 헬스체크 실패, SG가 헬스체크 포트 차단 |
| VPC Peering 후 통신 안 됨 | 양쪽 Route Table에 피어링 라우트 미추가 |
| CloudFront → ALB 접근 불가 | ALB SG에 CloudFront IP 대역 미허용 (Managed Prefix List 사용) |

---

## 비용 관련 판단

| 의사결정 포인트 | 저비용 선택 | 고비용 선택 | 비용 차이 |
|---------------|-----------|-----------|----------|
| S3/DynamoDB 접근 | Gateway Endpoint (무료) | NAT Gateway ($32/월+) | 월 $32+ 절약 |
| 소수 AWS 서비스 접근 | Interface Endpoint ($7.2/월) | NAT Gateway | 서비스 적으면 Endpoint 유리 |
| 많은 AWS 서비스 접근 | NAT Gateway 하나 | 서비스별 Interface Endpoint | NAT 하나가 더 쌈 |
| VPC 간 통신 | VPC Peering (무료*) | Transit Gateway ($0.05/GB) | 데이터 많으면 차이 큼 |

(*VPC Peering 자체는 무료, 크로스 AZ/리전 데이터 전송비만 발생)

---

## 네트워크 설계 시 판단 순서

```
1. Lambda/ECS가 뭘 호출해야 하나? → 인터넷? AWS 서비스? VPC 내부?
2. VPC에 넣어야 하나? → RDS/ElastiCache 접근 시만 Yes
3. 외부 나가는 경로는? → NAT Gateway vs VPC Endpoint
4. SG 설계: 최소 권한 (필요한 포트/IP만 열기)
5. NACL: 기본은 건드리지 않기 (SG로 충분). 명시적 차단 필요 시만 사용
```
