# observability

> 모니터링/로깅/알림 스택 가이드 — Prometheus, Grafana, ELK, Filebeat, alerting rules, dashboard 패턴

## When to Use

- Prometheus, Grafana, ELK, Kibana, Filebeat, Fluentd
- 모니터링, 알림, 메트릭, 로깅
- 대시보드, 알럿, 로그 수집, tracing, APM, 장애 감지

## What It Covers

- 3 Pillars: Metrics, Logs, Traces
- Prometheus (메트릭 타입, PromQL, recording rules, alerting rules)
- Grafana (대시보드 패턴, variable, panel 설계)
- ELK Stack (Elasticsearch + Logstash + Kibana)
- Filebeat / Fluentd 로그 수집 파이프라인
- AlertManager 설정 및 라우팅
- SLI/SLO 정의 및 에러 버짓

## References

- `references/` — alerting rules 템플릿, dashboard JSON

## Attribution

- Based on: [atilamedeiros/distributed-tracing](https://lobehub.com/skills/atilamedeiros-skills-distributed-tracing) + [pantheon-org/fluentbit-generator](https://lobehub.com/skills/pantheon-org-tekhne-fluentbit-generator) (Tier 2)
