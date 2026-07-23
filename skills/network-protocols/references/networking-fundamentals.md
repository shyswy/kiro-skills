# Networking Fundamentals for Developers

> Source: Jeff Bailey — "Fundamentals of Networking" (2025-12-13)
> URL: https://jeffbailey.us/blog/2025/12/13/fundamentals-of-networking/
> Content was rephrased for compliance with licensing restrictions.

## Core Mental Model

네트워크 장애는 4가지 관심사로 분리하면 명확해진다:

1. **Name Resolution (DNS)** — 이름을 IP로 변환
2. **Reachability (IP Routing)** — 패킷이 목적지에 도달 가능한가
3. **Transport (TCP/UDP)** — 프로세스 간 연결이 수립되는가
4. **Protocol & Security (HTTP, TLS)** — 응용 프로토콜이 정상 동작하는가

실패 시 가장 단순한 가정부터 시작해서 깊이 들어가며, 각 단계에서 증거를 수집한다.

---

## 요청의 End-to-End 흐름

`https://api.example.com/resource`를 호출할 때:

```
1. DNS    → 리졸버가 api.example.com의 IP 주소를 반환
2. Routing → 해당 IP로 패킷이 게이트웨이와 중간 네트워크를 거쳐 전달
3. Transport → 목적지 IP:443에 TCP 연결 수립
4. TLS    → 클라이언트-서버 간 암호화 및 신원 확인 협상
5. App    → 보호된 연결 위에서 HTTP 요청/응답 교환
```

---

## Packets and Layers

데이터는 작은 청크(packet)로 이동한다.

디버깅에 유용한 매핑:
- **Link Layer** — 로컬 네트워크 연결 (Ethernet, Wi-Fi)
- **Internet Layer** — 호스트/네트워크 간 라우팅 (IP)
- **Transport Layer** — 올바른 프로세스로 전달 (TCP, UDP)
- **Application Layer** — 앱이 사용하는 프로토콜 (HTTP, DNS)

---

## Addressing

### MAC Address
- 로컬 네트워크에서 NIC 식별
- 앱 코드에서 직접 사용하는 경우는 드묾
- ARP 디버깅 시 중요

### IP Address
- 네트워크에서 호스트 식별
- IPv4 (32-bit) vs IPv6 (128-bit)
- Dual stack 환경에서 한쪽만 실패할 수 있음

### Ports
- 호스트 위의 특정 앱 엔드포인트 식별
- 포트 틀리면 → connection error
- 방화벽이 차단하면 → timeout
- localhost만 listen하면 → 외부 접속 불가

---

## TCP vs UDP

### TCP (Transmission Control Protocol)
- Connection-oriented (3-way handshake)
- 신뢰성 있는 순서 보장 전달
- Flow control + Congestion control
- Retry는 보이지 않게 발생 → 앱은 그냥 느려짐
- Head-of-line blocking → 하나 지연되면 뒤에 줄줄이

### UDP (User Datagram Protocol)
- Connectionless
- 최소 오버헤드, 신뢰성/순서 보장 없음
- 실시간 음성/영상, 게임, DNS에 적합
- 신뢰성은 앱 또는 상위 프로토콜(QUIC)이 처리

---

## Common Error Messages

| 메시지 | 의미 |
|--------|------|
| **Connection refused** | 호스트 도달 가능하지만 포트에 리스너 없음, 또는 방화벽 reject |
| **Connection reset** | 수립된 연결이 갑자기 닫힘 (서버, 프록시, LB가 끊음) |
| **Timeout** | 클라이언트의 대기 한도 초과. 원인: 패킷 손실, 방화벽 drop, 서버/의존성 느림 |

**핵심:** timeout은 "서버가 느리다"는 뜻이 아님. 클라이언트가 포기했다는 뜻. 증거 없이는 원인 특정 불가.

---

## DNS

- **Recursive Resolver** — 호스트가 최초 질의하는 리졸버
- **Authoritative Nameserver** — 도메인의 진실의 원천
- **A Record** (IPv4), **AAAA Record** (IPv6)

### 흔한 DNS 문제
- 변경 후 캐시 stale
- Split Horizon DNS (내부/외부 뷰 다름)
- 마이그레이션 중 잘못된 레코드
- DNS 타임아웃 → "랜덤" 서비스 장애처럼 보임

**휴리스틱:** 빠른 실패 = DNS 의심. 느린 실패 = 라우팅/방화벽/전송 의심.

---

## TLS (Transport Layer Security)

TLS가 제공하는 것:
- **Encryption** (프라이버시)
- **Integrity** (변조 감지)
- **Authentication** (신원 확인)

### TLS 실패 증상
- 인증서 에러
- 핸드셰이크 실패
- "브라우저에선 되는데 코드에선 안 됨" — trust store 차이

### TLS는 인증서 문제만이 아님
- Clock skew (시간 틀어짐)
- 잘못된 SNI
- 중간 인증서 누락
- 구 버전 프로토콜 비활성화
- 기업 프록시 가로채기

---

## Performance 4요소

| 용어 | 의미 | 비유 |
|------|------|------|
| Latency | 지연 시간 | 여행 거리 |
| Bandwidth | 용량 | 고속도로 차선 수 |
| Jitter | 지연 변동 | 불규칙한 도착 시간 |
| Packet Loss | 데이터 미도착 | 택배 분실 |

- 분산 시스템에서 fan-out하면 latency가 쌓임
- Jitter → 시스템이 불안정하게 느껴짐
- Packet loss → TCP 재전송 → "서버 느림"으로 오진

---

## Troubleshooting: Evidence Ladder

### Step 1: Naming (DNS)
- 빠른 실패 → 잘못된 레코드 또는 DNS 뷰
- 느린 실패 → 리졸버 자체 문제, 네임서버 장애
- 환경마다 다른 결과 → 캐시, split-horizon, dual-stack

### Step 2: Reachability (Routing)
- 타임아웃 → 드랍, 블랙홀, 비대칭 경로
- 일부 목적지만 동작 → 라우팅 테이블 불완전
- 간헐적 → 경로 flapping, 혼잡

### Step 3: Transport (Ports & Handshakes)
- Connection refused → 도달했지만 리스너 없음
- Timeout → 경로 어딘가 드랍 (방화벽 silent drop)
- Reset → 연결 후 끊음 (서버, 프록시, LB)

### Step 4: Protocol & TLS
- 브라우저 vs 코드 차이 → trust store, 프록시, TLS 라이브러리 차이
- TLS 핸드셰이크 실패 → clock, 인증서, SNI, 프로토콜 버전
- 이상한 리다이렉트 → 잘못된 서비스/경로 (프록시, LB 설정)

---

## Misconceptions

| 오해 | 현실 |
|------|------|
| "DB가 문제야" | 서비스가 네트워크 호출을 기다리고 있으면 앱 속도는 제한 요소가 아님 |
| "타임아웃 = 서버가 느림" | 타임아웃 = 클라이언트가 포기함. 원인은 네트워크, 방화벽, 서버, 의존성 등 다양 |
| "TLS = 인증서 문제" | TLS 실패 원인: clock, SNI, 중간인증서, 프로토콜 버전, 프록시 가로채기 |

---

## References (원문)

- RFC 9293: TCP
- RFC 768: UDP
- RFC 791: IPv4
- RFC 8200: IPv6
- RFC 1034/1035: DNS
- RFC 9110: HTTP Semantics
- RFC 8446: TLS 1.3
- Kurose & Ross, "Computer Networking: A Top Down Approach"
- Stevens, "TCP/IP Illustrated, Volume 1"
