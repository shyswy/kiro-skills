---
name: network-protocols
description: |
  네트워크 프로토콜 계층 분류, 통신 패턴 선택, 트러블슈팅 가이드.
  새로운 통신을 설계할 때 각 레이어(Transport, Application Protocol, Communication Pattern,
  Data Handling, Message Format)별로 무엇을 쓸지 판단 근거와 함께 결정하도록 돕는다.
  "WebSocket은 TCP 레벨이야 HTTP 레벨이야?" 같은 계층 혼동을 바로잡고,
  상황별 프로토콜/통신 패턴 선택의 근거를 명확히 제시한다.
  이 스킬은 프로토콜 선택, 네트워크 설계 검토, 연결 이슈 트러블슈팅, AWS 네트워킹 질문에 사용한다.
  사용자가 "어떤 프로토콜 써야 해", "WebSocket vs SSE", "gRPC vs REST", "타임아웃 원인",
  "connection refused", "통신 설계", "실시간 기능 구현" 등을 언급하면 반드시 이 스킬을 활성화해야 한다.
  트리거: 네트워크, 프로토콜, TCP, UDP, HTTP, WebSocket, gRPC, MQTT, SSE, 계층, 레이어, OSI,
  통신 방식, 폴링, Long Polling, Pub/Sub, 실시간, 양방향, 연결 끊김, 타임아웃,
  connection refused, connection reset, DNS, TLS, 핸드셰이크, 포트, 방화벽,
  Security Group, NACL, VPC, 네트워크 설계, 프로토콜 선택, 어떤 프로토콜 써야,
  통신 설계, 스트리밍, stream 처리, 메모리 효율, chunk, binary, protobuf
license: MIT
---

# Network Protocols — 통신 설계 의사결정 가이드

## 이 Skill의 핵심 역할

새로운 통신을 설계할 때 **각 레이어별로 "왜 이걸 쓰는지"를 명시**하며 기술을 선택하도록 가이드한다.

단순히 "WebSocket 써" 가 아니라:
```
Application Protocol: WebSocket
├── 근거: 서버→클라, 클라→서버 양방향 실시간 필요 (키입력 + 화면 데이터)
├── 대안 검토: SSE → 단방향이라 키입력 전달 불가
├── 대안 검토: HTTP Polling → 100ms 미만 지연 요구에 폴링은 부적합
└── 결론: WebSocket이 유일한 합리적 선택
```

이런 식으로 **판단 과정을 투명하게** 만드는 게 목적이야.

---

## 통신 설계 체크리스트

새로운 통신 기능을 만들 때, 아래 5개 레이어 각각에서 선택 + 근거를 반드시 명시한다.

### Layer 1: Transport — "TCP vs UDP vs QUIC"

이 계층은 "데이터를 어떻게 실어 나르나"를 결정한다.

| 선택지 | 선택 조건 | 선택하면 안 되는 경우 |
|--------|----------|-------------------|
| **TCP** | 데이터 유실 불가, 순서 보장 필요, 대부분의 경우 기본값 | 극단적 저지연 요구 (게임 물리), 브로드캐스트 |
| **UDP** | 약간의 유실 허용 가능, 지연 최소화 우선 (영상/음성/게임) | 파일 전송, 금융 거래, DB 통신 |
| **QUIC** | HTTP/3 사용 시, 모바일 네트워크 (IP 변경 대응), 0-RTT 필요 | 레거시 시스템 호환 필요, UDP 차단 환경 |

**판단 근거 작성 예시:**
```
Transport: TCP
├── 근거: 디바이스 설정 명령이 유실되면 디바이스 상태 불일치 발생
├── UDP 불가: 명령 유실 허용 불가 (에어컨 온도를 25→18로 내리는데 유실되면 위험)
└── QUIC 불가: IoT 디바이스가 QUIC 미지원
```

---

### Layer 2: Application Protocol — "HTTP vs WebSocket vs gRPC vs MQTT vs SSE"

이 계층은 "어떤 규칙/형식으로 대화하나"를 결정한다.
**모두 L7(Application Layer)이며, TCP 위에서 동작한다** — TCP와 같은 레벨이 아님.

| 선택지 | 핵심 특성 | 선택 조건 | Scale-out 난이도 |
|--------|----------|----------|:---------------:|
| **HTTP** | Stateless, 요청-응답, 범용 | CRUD API, 외부 공개 API, 단발성 호출 | **쉬움** (Stateless, 아무 인스턴스나 처리) |
| **WebSocket** | Persistent, 양방향, 저지연 | 클라↔서버 양방향 실시간 (채팅, 원격제어, 게임) | **어려움** (Stateful → Sticky Session, Redis Pub/Sub 동기화 필요) |
| **SSE** | Persistent, 서버→클라 단방향 | 서버 Push만 필요 (알림, 로그, 피드) | **중간** (Stateful이지만 단방향이라 복잡도 낮음) |
| **gRPC** | HTTP/2, Protobuf, 타입 안전 | 서버↔서버 내부 RPC, 고성능 필요 | **쉬움** (L7 LB가 HTTP/2 멀티플렉싱 처리) |
| **MQTT** | Broker 경유, 극경량 | IoT, 배터리/대역폭 제한 환경 | **쉬움** (Broker가 스케일, 디바이스는 모름) |

**Scale-out이 선택에 미치는 영향:**
```
WebSocket을 선택하면:
├── ALB에서 Sticky Session (Connection ID 기반) 설정 필요
├── 서버 간 메시지 브로드캐스트에 Redis Pub/Sub 또는 별도 메시지 버스 필요
├── 배포 시 graceful shutdown (기존 연결 drain) 고려
└── 수평 확장 시 연결 수 = 서버 수 × 서버당 연결 한계 (보통 ~50K)

SSE를 선택하면:
├── HTTP 인프라 그대로 사용 가능 (ALB, CloudFront)
├── 연결은 Stateful이지만 클라→서버 요청이 없어 복잡도 낮음
└── 자동 재연결 내장으로 서버 교체 시에도 클라이언트가 알아서 복구
```

**판단 근거 작성 예시:**
```
Application Protocol: WebSocket
├── 근거: 클라이언트(키입력)→서버, 서버(화면)→클라이언트 양방향 동시 필요
├── HTTP 불가: 서버가 먼저 보낼 수 없음 (화면 변경을 Push 못함)
├── SSE 불가: 단방향 (서버→클라만). 키입력 전달에 별도 HTTP 필요 → 복잡도 증가
├── gRPC 불가: 브라우저 직접 지원 안 됨 (grpc-web 필요, 추가 프록시 레이어)
├── MQTT 불가: 브라우저 네이티브 미지원, Broker 인프라 불필요한 1:1 통신
└── Scale-out 대응: Redis Pub/Sub으로 서버 간 메시지 동기화, ALB Sticky Session 설정
```

#### 계층 혼동 방지 — 핵심 사실

```
WebSocket ≠ TCP 레벨. WebSocket은 L7(HTTP와 같은 레벨).
TCP를 "사용"하는 것이지 TCP와 "동급"이 아님.

비유: "택배(WebSocket)가 도로(TCP) 위에서 운행된다" ≠ "택배 = 도로"
```

```
HTTP/3 ≠ TCP. HTTP/3은 L7이고 QUIC(L4) 위에서 동작. QUIC는 UDP 위에서 TCP의 역할을 대신.
gRPC ≠ 별도 전송. gRPC는 L7이고 HTTP/2 위에서 동작.
MQTT ≠ UDP. MQTT는 TCP 기반 L7. "경량"이지만 QoS 위해 TCP 사용.
Kafka ≠ HTTP. 자체 바이너리 프로토콜 (TCP 기반 L7).
```

---

### Layer 3: Communication Pattern — "누가 먼저 보내고, 몇 대 몇인가"

프로토콜과 별개의 축이다. HTTP 위에서도 Polling, Long Polling, Webhook 모두 가능.

| 선택지 | 데이터 흐름 | 선택 조건 |
|--------|-----------|----------|
| **Request-Response** | 클라→서버→클라 (1회) | 단발성 조회, CRUD |
| **Short Polling** | 클라→서버 (N초 간격 반복) | 비동기 작업 상태 확인, 인프라 추가 없이 구현 |
| **Long Polling** | 클라→서버 (서버가 데이터 올 때까지 대기) | 준실시간, WebSocket 인프라 못 쓸 때 |
| **Server Push** | 서버→클라 (서버 주도) | 실시간 알림, 피드 |
| **Bidirectional** | 양방향 동시 | 채팅, 협업 편집, 원격 제어 |
| **Pub/Sub** | Publisher→Broker→N Subscribers | 1:N 이벤트 배포, MSA 서비스 간 |
| **Webhook** | 서버→클라의 HTTP 엔드포인트 | 비동기 이벤트 알림 (GitHub, Stripe) |

**판단 근거 작성 예시:**
```
Communication Pattern: Short Polling (3초 간격)
├── 근거: CSV Export는 30초~5분 소요. 실시간 필요 없고 "진행중/완료" 상태만 확인하면 됨
├── WebSocket 불가: Export 한 건 위해 연결 유지하는 건 과잉 (리소스 낭비)
├── Webhook 불가: 브라우저는 HTTP 서버가 아님 (Webhook 수신 불가)
├── Long Polling 불가: 구현 가능하지만 3초 Polling으로 충분한 UX (진행바)
└── 결론: 가장 단순한 구현으로 요구사항 충족
```

---

### Layer 4: Data Handling — "받은 데이터를 어떻게 소비하나"

통신 방식과 별개로, **받은 데이터를 메모리에서 어떻게 처리하느냐**의 문제.

| 선택지 | 동작 | 선택 조건 |
|--------|------|----------|
| **Batch** | 모아서 한 번에 처리 | 주기적 대량 처리, 실시간 불필요, 효율 우선 |
| **Stream** | 도착 즉시 chunk 단위 처리 | 대용량 데이터 (메모리에 안 올라감), 지연 최소화 |
| **Micro-batch** | 짧은 구간(초~분) 모아서 처리 | 스트림과 배치의 절충, 배치 도구 재활용 |

**판단 근거 작성 예시:**
```
Data Handling: Stream (Node.js ReadableStream)
├── 근거: VNC 화면 데이터가 초당 30프레임 × 수MB. 전체 버퍼링하면 메모리 폭발
├── Batch 불가: 1초치 모아서 처리하면 지연 1초 추가 → 원격 제어 UX 파괴
├── 구현: WebSocket 메시지를 받는 즉시 canvas에 렌더링 (버퍼 없이 흘려보냄)
└── 메모리 효과: 프레임 1개 크기(~100KB)만 메모리에 유지 vs 전체 버퍼링(수GB)
```

**"Stream"이라는 단어의 레이어별 의미:**
| 맥락 | 의미 | 레이어 |
|------|------|--------|
| Node.js Stream / ReadableStream | 코드에서 데이터를 chunk 단위로 처리하는 API | **런타임** |
| gRPC Streaming | RPC 호출에서 메시지를 연속 전송하는 프로토콜 기능 | **통신 패턴** |
| Kafka Streams | 이벤트를 도착 즉시 처리하는 아키텍처 | **데이터 처리** |
| HTTP Streaming | 응답을 chunked transfer로 끊어 보내는 방식 | **전송 기법** |

---

### Layer 5: Message Format — "데이터를 어떤 형태로 주고받나"

| 선택지 | 특성 | 선택 조건 |
|--------|------|----------|
| **JSON** | 사람 읽기 쉬움, 범용, 파싱 비용 있음 | REST API, 디버깅 중요, 페이로드 작을 때 |
| **Protobuf** | 바이너리, 작음, 타입 안전, 코드 생성 | gRPC, 서버간 고빈도 통신, 스키마 엄격 |
| **Binary (custom)** | 최소 오버헤드, 완전 제어 | 영상/음성 데이터, 극한 성능, IoT 센서 raw |
| **MessagePack** | JSON 호환 바이너리, JSON보다 30% 작음 | JSON이 필요하지만 크기 줄이고 싶을 때 |
| **Avro** | 스키마 레지스트리, 진화 가능 | Kafka 이벤트, 스키마 버전 관리 필요 |

**판단 근거 작성 예시:**
```
Message Format: Binary (ArrayBuffer)
├── 근거: VNC 화면 데이터는 픽셀 raw data. JSON 인코딩하면 Base64로 33% 증가
├── JSON 불가: 30fps × 100KB frame을 매번 Base64 인코딩하면 대역폭 낭비 + CPU 부하
├── Protobuf 불가: 프레임은 이미 바이너리 blob이라 직렬화 이점 없음
└── 결론: WebSocket Binary Frame으로 raw 전송이 최적
```

---

## 출력 템플릿

통신 설계 요청에 대한 응답은 아래 형태를 따른다:

```markdown
## [기능명] 통신 설계

### 요구사항 요약
- 통신 주체: [누구 ↔ 누구]
- 방향성: [단방향/양방향]
- 지연 요구: [실시간/준실시간/비동기]
- 데이터 특성: [크기, 빈도, 형태]
- 제약 조건: [브라우저 지원, 인프라 제한, 디바이스 제약 등]

### 레이어별 선택

| Layer | 선택 | 근거 (한 줄) |
|-------|------|-------------|
| Transport | TCP | 데이터 유실 불가 |
| App Protocol | WebSocket | 양방향 실시간 |
| Pattern | Bidirectional Push | 서버/클라 모두 주도적 전송 |
| Data Handling | Stream | 메모리 효율 (프레임 단위 처리) |
| Format | Binary | raw 픽셀 데이터, 인코딩 오버헤드 제거 |

### 상세 근거

#### 1. Transport: TCP
- 근거: ...
- 대안 검토: UDP → ... (불가 이유)

#### 2. Application Protocol: WebSocket
- 근거: ...
- 대안 검토: SSE → ... (불가 이유)
- 대안 검토: HTTP → ... (불가 이유)

(이하 각 레이어 동일 패턴)
```

---

## 설계 예시

### 예시 1: VNC 원격 제어 (Device → Cloud → Browser)

| Layer | 선택 | 근거 |
|-------|------|------|
| Transport | TCP | 화면/키입력 유실 불가 |
| App Protocol | WebSocket | 양방향 실시간 (키입력 ↔ 화면) |
| Pattern | Bidirectional | 서버→화면, 클라→키입력 동시 |
| Data Handling | Stream | 프레임 단위 즉시 렌더링, 메모리 효율 |
| Format | Binary | 픽셀 데이터 raw 전송, JSON 인코딩 오버헤드 제거 |

### 예시 2: CSV Export 상태 확인 (Browser → API)

| Layer | 선택 | 근거 |
|-------|------|------|
| Transport | TCP | HTTP 기반이므로 TCP 자동 |
| App Protocol | HTTP | 단순 상태 조회, Stateless 충분 |
| Pattern | Short Polling (3초) | 30초~5분 작업, 실시간 불필요 |
| Data Handling | Batch (응답 전체) | 상태 JSON 한 건 (<1KB) |
| Format | JSON | 디버깅 용이, 작은 페이로드 |

### 예시 3: IoT 디바이스 상태 리포트 (Device → Cloud)

| Layer | 선택 | 근거 |
|-------|------|------|
| Transport | TCP | MQTT가 TCP 기반, QoS 보장 필요 |
| App Protocol | MQTT (QoS 1) | 배터리/대역폭 제한, 2바이트 최소 헤더 |
| Pattern | Pub/Sub | 1:N (디바이스→여러 소비자), 디커플링 |
| Data Handling | Micro-batch | 센서 값 10초 모아서 1회 전송 (배터리 절약) |
| Format | JSON (compact) | 디버깅 필요, 페이로드 작음 (<200B) |

### 예시 4: MSA 서비스 간 동기 호출 (Service → Service)

| Layer | 선택 | 근거 |
|-------|------|------|
| Transport | TCP | HTTP/2 기반 |
| App Protocol | gRPC | 타입 안전, 코드 생성, JSON 대비 10x 작은 페이로드 |
| Pattern | Request-Response (Unary) | 단발성 조회/명령 |
| Data Handling | Batch (응답 전체) | 응답이 작음 (KB 단위) |
| Format | Protobuf | gRPC 기본, 스키마 강제, 호환성 관리 |

---

## 트러블슈팅 — Evidence Ladder

통신 문제 발생 시 **아래 계층부터 위로** 검증:

```
Step 1: DNS → dig / nslookup
Step 2: Reachability → ping / traceroute  
Step 3: Port → nc -zv host port / telnet
Step 4: TLS → openssl s_client -connect host:443
Step 5: Application → curl -v / httpie
```

| 증상 | 의심 계층 | 확인 방법 |
|------|----------|----------|
| `name not found` | DNS | `dig domain.com` |
| `no route to host` | L3 (라우팅) | `traceroute host` |
| `connection refused` | L4 (포트 안 열림) | `nc -zv host port` |
| `connection timed out` | L3/L4 (방화벽 drop) | `tcptraceroute host port` |
| `connection reset` | L4/L7 (서버가 끊음) | 서버 로그, LB 로그 |
| `SSL handshake failure` | TLS | `openssl s_client` |
| `502/503/504` | L7 (LB/프록시) | LB 로그, 백엔드 health |

**핵심:** timeout ≠ "서버가 느림". timeout = "클라이언트가 포기함". 원인은 네트워크, 방화벽, 서버, 의존성 등 다양.

---

## 참고 자료

상세 레퍼런스가 필요할 때 아래 파일 참조:

- `references/networking-fundamentals.md` — 개발자용 네트워킹 기초 (Jeff Bailey, 계층 모델, 트러블슈팅 mental model)
- `references/protocol-comparison.md` — ByteByteGo 8대 프로토콜 비교
- `references/realtime-protocol-decision.md` — 실시간 프로토콜 선택 Decision Guide (websocket.org)
- `references/aws-networking.md` — AWS VPC, Security Group vs NACL, NAT, VPC Endpoint 의사결정 가이드
- `#[[file:notes/network_protocols.md]]` — 개인 학습 노트 (통신 패턴, 데이터 처리, 프로젝트 적용 사례)

---

## 심화 시 참조할 Skill

이 skill은 "어떤 프로토콜/패턴을 선택할까"까지만 다룬다. 선택 후 구현 단계에서는:

| 심화 주제 | 참조 Skill | 언제 전환하나 |
|-----------|-----------|-------------|
| Kafka Consumer/Producer 구현 | `kafka-msk`, `nodejs-kafka` | Pub/Sub 패턴에서 Kafka를 선택한 후 |
| MQTT/IoT Core 메시지 파이프라인 | `iot-messaging` | MQTT 선택 후 디바이스 리포트 정규화, Rule Engine 설계 시 |
| gRPC 서비스 간 통신 구현 | `api-design` | gRPC 선택 후 .proto 설계, 에러 코드 설계 시 |
| WebSocket/SSE 구현 (Node.js) | `nodejs-typescript` | 프로토콜 선택 후 서버/클라이언트 코드 작성 시 |
| AWS VPC/네트워크 인프라 | `aws-serverless-eda`, `k8s-eks` | 네트워크 트러블슈팅에서 인프라 설정 변경이 필요할 때 |
| 이벤트 스키마 계약 관리 | `contract-testing` | Pub/Sub 패턴 구현 후 Producer-Consumer 계약 검증 시 |
