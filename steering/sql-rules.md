---
inclusion: fileMatch
fileMatchPattern: "*.sql,*migration*"
---

# SQL Rules

## 스타일
- 키워드 대문자 (SELECT, FROM, WHERE, JOIN)
- 테이블/컬럼명 snake_case
- 들여쓰기 2칸
- 서브쿼리보다 CTE (WITH) 선호

## 테이블 설계
- PK는 id (bigint auto-increment 또는 UUID)
- created_at, updated_at 필수
- soft delete 시 deleted_at 컬럼
- FK에 인덱스 필수
- ENUM 대신 별도 참조 테이블 또는 CHECK constraint

## 인덱스
- WHERE/JOIN 조건 컬럼에 인덱스
- 복합 인덱스는 카디널리티 높은 컬럼 먼저
- LIKE '%keyword' 패턴은 인덱스 불가 인지

## Migration
- 파일명: timestamp_description.sql (예: 20250522_add_user_email_index.sql)
- UP/DOWN 모두 작성
- 데이터 마이그레이션과 스키마 마이그레이션 분리
- 대용량 테이블 ALTER는 online DDL 또는 pt-osc 고려
