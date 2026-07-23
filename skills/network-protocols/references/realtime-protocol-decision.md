# Real-Time Protocol Decision Guide

> Source: websocket.org — "Real-Time Protocol Decision Guide" & "WebSocket vs TCP"
> URLs:
>   - https://websocket.org/comparisons/decision-guide/
>   - https://websocket.org/comparisons/
>   - https://websocket.org/reference/websocket-vs-tcp/
> Content was rephrased for compliance with licensing restrictions.

---

## "WebSocket vs TCP" — 계층 혼동 해소

**WebSocket은 TCP의 대안이 아니다. TCP 위에서 동작한다.**

WebSocket 연결 = TCP 연결 + 메시지 프레이밍 + HTTP 호환 핸드셰이크 + 브라우저 접근성

"WebSocket vs TCP"라고 말하는 건 "HTTP vs TCP"라고 말하는 것과 같다 — 다른 레이어지, 경쟁 선택지가 아니다.

```
┌───────────────────────┐
│  WebSocket (L7)       │  ← 메시지 프레이밍, 양방향 Push
├───────────────────────┤
│  TLS (optional)       │  ← wss:// 사용 시
├───────────────────────┤
│  TCP (L4)             │  ← 신뢰성, 순서 보장
├───────────────────────┤
│  IP (L3)              │  ← 라우팅
└───────────────────────┘
```

---

## Real-Time Protocol Comparison Summary

### WebSocket
- **양방향 풀-듀플렉스**, 브라우저 지원 99%+
- 온라인 게임, 실시간 채팅, 협업 편집, 라이브 대시보드
- 연결 유지 (Persistent), 서버/클라 모두 언제든 메시지 전송 가능
- **단점:** Stateful → Scale-out 시 sticky session 필요, 연결 끊기면 직접 재연결 구현

### SSE (Server-Sent Events)
- **단방향** (서버 → 클라이언트만)
- 뉴스 피드, 주식 시세, 알림 스트림, 로그 뷰어
- 표준 HTTP 위에서 동작 (chunked transfer)
- 자동 재연결 내장
- **단점:** 단방향만 가능, HTTP/1.1에서 도메인당 연결 6개 제한

### Long Polling
- **호환성 100%** (모든 HTTP 서버 지원)
- WebSocket/SSE를 쓸 수 없는 환경에서의 대안
- 서버가 데이터 올 때까지 응답 보류 → 준실시간
- **단점:** 불필요한 연결 재수립, 서버 리소스 점유

### HTTP/2 Server Push
- 서버가 클라이언트 요청 없이 리소스 Push
- 주로 정적 리소스 (CSS, JS) 미리 보내기용
- **WebSocket 대체 아님** — 임의의 실시간 데이터 Push에는 부적합
- 대부분 브라우저에서 deprecated 추세

### WebRTC
- **P2P** 미디어 스트리밍 (음성, 영상)
- 중앙 서버 없이 클라이언트끼리 직접 통신
- **단점:** 시그널링 서버는 별도 필요, NAT traversal 복잡

---

## Decision Flowchart

```
브라우저에서 실시간이 필요한가?
├── Yes
│   ├── 양방향 데이터 교환이 빈번한가? (채팅, 게임, 협업)
│   │   └── Yes → WebSocket
│   │
│   ├── 서버→클라 단방향이면 충분한가? (알림, 피드, 로그)
│   │   └── Yes → SSE
│   │
│   ├── P2P 미디어가 필요한가? (영상통화, 화면공유)
│   │   └── Yes → WebRTC
│   │
│   └── 어떤 환경에서도 동작해야 하나? (프록시, 방화벽 제한)
│       └── Yes → Long Polling (fallback)
│
└── No (서버 ↔ 서버)
    ├── 타입 안전한 고성능 RPC → gRPC (HTTP/2)
    ├── 비동기 이벤트 전달 → Kafka / SQS / EventBridge
    └── 범용 REST API → HTTP
```

---

## Key Takeaway

**"어떤 실시간 프로토콜을 쓸까?"의 기본 답:**

1. 대부분의 실시간 웹앱 → **WebSocket** (양방향, 성숙한 생태계)
2. 서버 Push만 필요 → **SSE** (단순, HTTP 표준)
3. IoT 디바이스 → **MQTT** (경량, QoS)
4. P2P 미디어 → **WebRTC**
5. 백엔드 서비스 간 → **gRPC** (성능, 타입 안전)
