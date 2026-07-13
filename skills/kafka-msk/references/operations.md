# Kafka 운영 가이드

## Topic 마이그레이션

### 시나리오: 매핑/스키마 변경으로 새 topic 필요

```
1. 새 topic 생성 (new-topic)
2. Dual-write: Producer가 old-topic + new-topic 동시 발행
3. Consumer를 new-topic으로 전환 (하나씩)
4. 모든 consumer 전환 완료 확인
5. old-topic Producer 중단
6. old-topic retention 만료 후 삭제
```

### 데이터 복사 (MirrorMaker2 / kafka-streams)
```bash
# MirrorMaker2로 topic 간 복사
kafka-mirror-maker.sh --consumer.config source.properties \
  --producer.config target.properties \
  --whitelist "old-topic"
```

### Kafka Streams 기반 변환 마이그레이션
```java
// old 포맷 → new 포맷 변환하면서 마이그레이션
KStream<String, OldFormat> source = builder.stream("old-topic");
source.mapValues(old -> convertToNewFormat(old))
      .to("new-topic");
```

---

## Partition 증설

### 절차
```bash
kafka-topics.sh --bootstrap-server broker:9092 \
  --alter --topic my-topic --partitions 12
```

### ⚠️ 주의사항
- 파티션 수는 증가만 가능 (감소 불가)
- Key 기반 파티셔닝 시: 기존 key→partition 매핑 깨짐
  - 해결: 새 topic으로 마이그레이션 (위 절차)
  - 또는: Custom Partitioner로 호환성 유지
- Compacted topic: 증설 후 같은 key가 다른 파티션에 존재 가능
- Consumer group: 자동 rebalance 발생

### 파티션 수 결정 공식
```
파티션 수 = max(
  목표 처리량(MB/s) / 단일 파티션 처리량(MB/s),
  최대 consumer 수
)
```
- 단일 파티션 처리량: 보통 10MB/s (producer), 30MB/s (consumer)
- 여유분: 1.5~2배 (향후 확장 고려)

---

## 클러스터 업그레이드 (MSK)

### Rolling Upgrade 절차
1. MSK 콘솔에서 클러스터 버전 업그레이드 시작
2. 브로커가 하나씩 재시작 (자동)
3. 모니터링: UnderReplicatedPartitions = 0 확인
4. 완료 후 inter.broker.protocol.version 업데이트

### 다운타임 최소화
- min.insync.replicas=2, replication.factor=3 설정
- unclean.leader.election.enable=false
- 업그레이드 중 Producer/Consumer 정상 동작 (rolling이므로)

---

## Consumer Group 관리

### Offset Reset
```bash
# Dry-run (확인만)
kafka-consumer-groups.sh --bootstrap-server broker:9092 \
  --group my-group --topic my-topic \
  --reset-offsets --to-earliest --dry-run

# 실행 (consumer 중지 상태에서)
kafka-consumer-groups.sh --bootstrap-server broker:9092 \
  --group my-group --topic my-topic \
  --reset-offsets --to-earliest --execute

# 특정 시간으로
--reset-offsets --to-datetime "2026-05-20T00:00:00.000"

# 특정 offset으로
--reset-offsets --to-offset 1000
```

### Consumer Group 삭제
```bash
# 모든 consumer 중지 후
kafka-consumer-groups.sh --bootstrap-server broker:9092 \
  --group my-group --delete
```

### Lag 모니터링 자동화
```yaml
# CloudWatch 알람 (MSK)
MetricName: MaxOffsetLag
Namespace: AWS/Kafka
Dimensions:
  - Name: Consumer Group
    Value: my-group
  - Name: Topic
    Value: my-topic
Threshold: 10000  # lag > 10000이면 알람
```

---

## Topic 설정 변경

### Retention 변경
```bash
kafka-configs.sh --bootstrap-server broker:9092 \
  --alter --entity-type topics --entity-name my-topic \
  --add-config retention.ms=604800000  # 7일

# Compaction 활성화
--add-config cleanup.policy=compact

# Compact + Delete (둘 다)
--add-config cleanup.policy=compact,delete
```

### 설정 확인
```bash
kafka-configs.sh --bootstrap-server broker:9092 \
  --describe --entity-type topics --entity-name my-topic
```

---

## 장애 대응

### Broker 장애
| 증상 | 원인 | 대응 |
|------|------|------|
| UnderReplicatedPartitions > 0 | Broker 다운/느림 | 해당 broker 상태 확인, 재시작 |
| OfflinePartitionsCount > 0 | Leader 없는 파티션 | preferred leader election 실행 |
| Producer timeout | Broker 응답 없음 | 네트워크/디스크 확인 |

### Consumer 장애
| 증상 | 원인 | 대응 |
|------|------|------|
| Lag 급증 | Consumer 처리 느림 | 처리 로직 최적화 또는 scale-out |
| Frequent rebalance | Consumer 불안정 | session.timeout 증가, static membership |
| Commit 실패 | Coordinator 변경 | 자동 복구 대기, 재시작 |

### 데이터 유실 방지 체크리스트
- [ ] acks=all (Producer)
- [ ] min.insync.replicas=2
- [ ] replication.factor=3
- [ ] unclean.leader.election.enable=false
- [ ] enable.auto.commit=false (Consumer)
- [ ] 처리 완료 후 수동 커밋

---

## MSK 특화 운영

### MSK Configuration 변경
```bash
aws kafka update-cluster-configuration \
  --cluster-arn arn:aws:kafka:... \
  --configuration-info '{"Arn":"arn:aws:kafka:...:configuration/...","Revision":2}' \
  --current-version "K1..."
```

### MSK 모니터링 핵심 메트릭
| 메트릭 | 임계값 | 의미 |
|--------|--------|------|
| CpuUser | > 60% | 브로커 CPU 과부하 |
| KafkaDataLogsDiskUsed | > 85% | 디스크 부족 |
| UnderReplicatedPartitions | > 0 | 복제 지연 |
| GlobalPartitionCount | > 1000/broker | 파티션 과다 |
| EstimatedMaxTimeLag | > 허용치 | Consumer lag |

### MSK Tiered Storage
```bash
# Topic에 tiered storage 활성화
kafka-configs.sh --alter --entity-type topics --entity-name my-topic \
  --add-config remote.storage.enable=true \
  --add-config local.retention.ms=86400000  # 로컬 1일, 나머지 S3
```
