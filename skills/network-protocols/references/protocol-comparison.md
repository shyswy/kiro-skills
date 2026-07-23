# 8 Popular Network Protocols — Quick Reference

> Source: ByteByteGo — "Explaining 8 Popular Network Protocols in 1 Diagram"
> URL: https://blog.bytebytego.com/p/ep80-explaining-8-popular-network
> Additional: https://bytebytego.com/guides/guides/explaining-8-popular-network-protocols-in-1-diagram/
> Content was rephrased for compliance with licensing restrictions.

---

## Protocol Stack Overview

```
Application Layer (L7)
├── HTTP/1.1  — 웹의 기반, 요청-응답, text 헤더
├── HTTP/2    — 멀티플렉싱, 헤더 압축, 서버 푸시
├── HTTP/3    — QUIC 위에서 동작 (UDP 기반), 모바일 최적화
├── HTTPS     — HTTP + TLS 암호화
├── WebSocket — 풀-듀플렉스 양방향, 실시간
├── SMTP      — 이메일 전송
├── FTP       — 파일 전송
└── (기타 application protocols)

Transport Layer (L4)
├── TCP       — 신뢰성, 순서 보장, 연결 지향
├── UDP       — 경량, 비연결, 순서/신뢰 보장 없음
└── QUIC      — UDP 위에서 TCP 수준 신뢰성 + 0-RTT

Network Layer (L3)
└── IP        — 패킷 라우팅, 주소 지정
```

---

## 8 Protocols Compared

### 1. HTTP/1.1
- 웹 통신의 기반
- 요청-응답 모델, text 기반 헤더
- Keep-Alive로 연결 재사용 가능
- **한계:** Head-of-line blocking (하나의 요청이 막히면 뒤가 대기)

### 2. HTTP/2
- 단일 TCP 연결 위에서 멀티플렉싱
- 헤더 압축 (HPACK)
- Server Push (서버가 요청 안 받아도 보냄)
- **한계:** TCP 레벨 HOL blocking은 여전히 존재

### 3. HTTP/3
- QUIC 위에서 동작 (UDP 기반 transport)
- TCP의 HOL blocking 완전 해결
- 0-RTT 연결 (재연결 시 지연 거의 없음)
- 모바일 네트워크 (IP 변경 시에도 연결 유지)에 유리
- **VR/고대역폭 앱에 유리**

### 4. HTTPS
- HTTP에 TLS/SSL 암호화 추가
- 데이터 보호 (도청, 변조 방지)
- 인증서로 서버 신원 확인
- **현대 웹에서 사실상 필수** (브라우저가 HTTP를 경고 표시)

### 5. WebSocket
- HTTP에서 Upgrade 핸드셰이크 후 풀-듀플렉스 전환
- 양방향 실시간 통신
- 서버가 클라이언트에 데이터 Push 가능
- **사용처:** 온라인 게임, 주식 트레이딩, 메시징 앱
- **REST와 차이:** REST는 항상 "pull", WebSocket은 "push" 가능

### 6. TCP (Transmission Control Protocol)
- 인터넷에서 패킷을 보내고 성공적 전달을 보장
- 순서 보장, 재전송, 흐름 제어, 혼잡 제어
- **대부분의 L7 프로토콜이 TCP 위에 구축됨**
- 3-way handshake (SYN → SYN-ACK → ACK)

### 7. UDP (User Datagram Protocol)
- 연결 수립 없이 바로 전송
- 신뢰성/순서 보장 없음
- **시간 민감한 통신에 적합** — 가끔 패킷 유실이 기다리는 것보다 나은 경우
- **사용처:** 음성, 영상, DNS, 게임

### 8. SMTP (Simple Mail Transfer Protocol)
- 이메일 전송 프로토콜
- 서버 간 릴레이 방식
- TCP 기반 (포트 25/587)

---

## Key Insight: Layer Relationships

```
HTTP/3 ─── uses ──→ QUIC ─── uses ──→ UDP
HTTP/2 ─── uses ──→ TCP
HTTP/1.1 ── uses ──→ TCP
WebSocket ── uses ──→ TCP (HTTP Upgrade 후)
gRPC ────── uses ──→ HTTP/2 ─── uses ──→ TCP
MQTT ────── uses ──→ TCP
```

**"uses"는 "위에서 동작한다"는 뜻.** 
상위 프로토콜은 하위 프로토콜의 기능(신뢰성, 라우팅)을 이용하면서
자신만의 기능(메시지 형식, 의미)을 추가한다.

---

## When to Use What (ByteByteGo Decision Guide)

| 요구사항 | 프로토콜 |
|---------|---------|
| 일반 웹 API | HTTP/1.1 or HTTP/2 (REST) |
| 실시간 양방향 (게임, 채팅) | WebSocket |
| 서버→클라 단방향 스트림 | SSE (HTTP) |
| 모바일/불안정 네트워크 | HTTP/3 (QUIC) |
| 서비스 간 고성능 RPC | gRPC (HTTP/2) |
| IoT 경량 메시징 | MQTT |
| 영상/음성 스트리밍 | UDP (또는 WebRTC) |
| 이메일 | SMTP |

---

## Source Attribution

- ByteByteGo Newsletter EP80 (2023-10-07)
- ByteByteGo System Design 101 (GitHub: ByteByteGoHq/system-design-101)
- websocket.org — Real-Time Protocol Decision Guide (2025)
