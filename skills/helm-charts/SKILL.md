---
name: helm-charts
description: |
  Helm 차트 작성, 관리, 배포 가이드. values 설계, template 패턴,
  dependency 관리, release 전략을 다룬다.
  트리거: Helm, chart, values, template, release, helm install, helm upgrade, 헬름, 차트, 배포, 패키징, 쿠버네티스 배포
license: MIT
---

# Helm Charts Guide

## 차트 구조
```
my-chart/
├── Chart.yaml          # 메타데이터, 의존성
├── values.yaml         # 기본 설정값
├── templates/
│   ├── _helpers.tpl    # 공통 템플릿 함수
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   └── NOTES.txt       # 설치 후 안내
└── charts/             # 의존성 차트
```

## values.yaml 설계
- 최상위: 리소스 종류별 그룹핑 (image, service, ingress, resources)
- 환경별 override: values-dev.yaml, values-prod.yaml
- 민감 정보는 values에 넣지 않음 (External Secrets 또는 sealed-secrets)

## Template 패턴
- _helpers.tpl: fullname, labels, selectorLabels 정의
- 조건부 리소스: {{- if .Values.ingress.enabled }}
- range로 반복: 여러 포트, 환경변수
- toYaml | nindent로 복잡한 구조 삽입

## 의존성 관리
- Chart.yaml의 dependencies 섹션
- helm dependency update로 lock 파일 생성
- condition 필드로 선택적 활성화

## 배포 전략
- helm upgrade --install (idempotent)
- --atomic: 실패 시 자동 롤백
- --wait: 모든 리소스 ready 대기
- helm rollback: 이전 revision으로 복원

## 테스트
- helm template로 렌더링 확인
- helm lint로 문법 검증
- helm test로 연결 테스트 (test pod)

---

## MCP 연동

이 스킬은 특정 MCP에 의존하지 않음. Helm 차트 작성/관리 가이드 목적.
- EKS 배포 시 → `k8s-eks` 스킬 참조
- ArgoCD 연동 시 → `gitops-cicd` 스킬 참조
- GitLab에서 차트 관리 시 → `git-gitlab` 스킬 (gitlab-mcp MCP로 파일 조회/수정 가능)
