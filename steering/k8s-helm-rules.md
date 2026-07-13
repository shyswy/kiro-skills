---
inclusion: fileMatch
fileMatchPattern: "**/k8s/**/*.yaml,**/k8s/**/*.yml,**/helm/**/*.yaml,**/helm/**/*.yml,**/charts/**/*.yaml,**/charts/**/*.yml,**/manifests/**/*.yaml,**/manifests/**/*.yml,**/deploy/**/*.yaml,**/deploy/**/*.yml,**/templates/**/*.yaml"
---

# Kubernetes / Helm Rules

## K8s Manifest
- apiVersion 명시 (최신 stable 사용)
- metadata.labels 필수: app, version, component, managed-by
- resource requests/limits 필수 설정
- liveness/readiness probe 필수
- securityContext: runAsNonRoot, readOnlyRootFilesystem
- namespace 명시 (default 사용 금지)

## Helm Chart
- values.yaml에 모든 설정 가능한 값 노출
- _helpers.tpl로 공통 라벨/이름 템플릿화
- Chart.yaml의 appVersion과 이미지 태그 일치
- NOTES.txt로 설치 후 안내 제공

## 네이밍
- 리소스명: {{ .Release.Name }}-{{ .Chart.Name }}-component
- ConfigMap/Secret: 용도 명확히 (예: app-config, db-credentials)

## 주의
- 이 규칙은 K8s/Helm yaml에만 적용
- 일반 config yaml (package.json 관련 등)에는 적용하지 않음
