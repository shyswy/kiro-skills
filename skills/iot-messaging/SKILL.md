---
name: iot-messaging
description: |
  IoT Core, MQTT 메시지 파이프라인, 디바이스 리포트 정규화 패턴 가이드.
  diff/full/snapshot 메시지, normalizer, CDC 패턴을 다룬다.
  트리거: IoT Core, MQTT, device report, diff, full, snapshot, normalizer, CDC, 디바이스, 센서, 텔레메트리, 메시지 파이프라인, 정규화
license: MIT
---

# IoT Messaging Patterns

## MQTT 기본
- Topic 구조: devices/{deviceId}/telemetry, devices/{deviceId}/commands
- QoS 레벨: 0(최대 1회), 1(최소 1회, 권장), 2(정확히 1회, 오버헤드 큼)
- Retained message: 마지막 상태 유지 (새 구독자에게 즉시 전달)
- Last Will: 디바이스 비정상 종료 감지

## 디바이스 리포트 유형

### Full Report
- 디바이스 전체 상태를 매번 전송
- 장점: 수신 측 상태 복원 용이
- 단점: 대역폭 낭비

### Diff Report
- 이전 대비 변경된 필드만 전송
- 장점: 대역폭 절약
- 단점: 수신 측에서 상태 조합 필요, 유실 시 불일치

### Snapshot
- 주기적 전체 상태 (예: 1시간마다)
- diff 유실 시 복구 기준점

## Normalizer 패턴
- 다양한 디바이스 프로토콜/포맷을 통일된 내부 포맷으로 변환
- 입력: 디바이스별 raw payload
- 출력: 표준화된 이벤트 (timestamp, deviceId, metrics{})
- 구현: Lambda 또는 Kafka Streams transform

## CDC (Change Data Capture) 연동
- 디바이스 상태 변경 → DB 저장 → CDC로 다운스트림 전파
- DynamoDB Streams 또는 Kafka Connect
- 이벤트 순서 보장: partition key = deviceId

## AWS IoT Core 특화
- Rule Engine: MQTT → Lambda, Kinesis, S3, DynamoDB
- Device Shadow: 디바이스 desired/reported 상태 관리
- Fleet Indexing: 대규모 디바이스 검색/집계

---

## MCP 연동

### 사용 MCP: aws-cloudwatch
- 상태: ✅ 연동됨 (user-scope-config.md 참조)
- 활용 시나리오:
  - IoT Rule 실행 메트릭: `mcp_aws_cloudwatch_get_metric_data` (namespace: AWS/IoT)
  - 주요 메트릭: RuleMessageThrottled, TopicMatch, PublishIn.Success
  - 디바이스 연결 상태: Connect.Success, Disconnect
  - 로그 분석: IoT Core 로그 → CloudWatch Logs → `mcp_aws_cloudwatch_execute_log_insights_query`

### 참고
- IoT Core 직접 관리 (thing 생성, rule 설정 등)는 MCP 미지원 → AWS CLI 또는 CDK 사용
- Kafka 연동 시 → `kafka-msk` 스킬 참조
