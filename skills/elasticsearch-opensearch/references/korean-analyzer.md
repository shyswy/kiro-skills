# 한국어 분석기 설정 가이드

## Nori 분석기 기본 설정

```json
PUT /my-index
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "nori_tokenizer": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed",
          "discard_punctuation": true,
          "user_dictionary": "userdict_ko.txt"
        }
      },
      "analyzer": {
        "korean": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": [
            "nori_readingform",
            "lowercase",
            "nori_part_of_speech",
            "korean_synonym",
            "korean_stop"
          ]
        },
        "korean_search": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": [
            "nori_readingform",
            "lowercase",
            "korean_synonym"
          ]
        }
      },
      "filter": {
        "nori_part_of_speech": {
          "type": "nori_part_of_speech",
          "stoptags": [
            "E", "IC", "J", "MAG", "MAJ",
            "MM", "SP", "SSC", "SSO", "SC",
            "SE", "XPN", "XSA", "XSN", "XSV",
            "UNA", "NA", "VSV"
          ]
        },
        "korean_synonym": {
          "type": "synonym_graph",
          "synonyms_path": "analysis/synonyms_ko.txt"
        },
        "korean_stop": {
          "type": "stop",
          "stopwords_path": "analysis/stopwords_ko.txt"
        }
      }
    }
  }
}
```

---

## Decompound Mode

| 모드 | 입력 "삼성전자" | 출력 | 용도 |
|------|---------------|------|------|
| none | 삼성전자 | [삼성전자] | 원형 유지 |
| discard | 삼성전자 | [삼성, 전자] | 분리만 |
| mixed | 삼성전자 | [삼성전자, 삼성, 전자] | **권장** (원형+분리 모두 검색) |

---

## 사용자 사전 (userdict_ko.txt)

### 위치
- OpenSearch: `config/analysis/userdict_ko.txt`
- Docker: 볼륨 마운트 또는 패키지에 포함

### 형식
```
# 복합명사 분리 규칙
삼성전자 삼성 전자
인공지능 인공 지능
머신러닝
딥러닝

# 고유명사 (분리하지 않음)
LG전자
네이버클라우드
```

### 사전 업데이트 절차
1. userdict_ko.txt 수정
2. 인덱스 close → open (analyzer 재로드)
   ```json
   POST /my-index/_close
   POST /my-index/_open
   ```
3. 또는 reindex (기존 문서에 새 사전 적용 필요 시)

---

## 동의어 설정 (synonyms_ko.txt)

### 형식
```
# 동의어 그룹 (양방향)
노트북, 랩탑, laptop
핸드폰, 스마트폰, 휴대폰, mobile

# 단방향 (왼쪽 → 오른쪽으로 확장)
TV => 텔레비전, 티비
AI => 인공지능, artificial intelligence
```

### Search-time vs Index-time 동의어

| 방식 | 장점 | 단점 |
|------|------|------|
| Index-time (synonym) | 검색 빠름 | 동의어 변경 시 reindex 필요 |
| Search-time (synonym_graph) | 동의어 변경 즉시 반영 | 검색 시 약간 느림 |

**권장**: search analyzer에 `synonym_graph` 사용 (유연성)

```json
{
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "analyzer": "korean",           // index-time: 동의어 없이
        "search_analyzer": "korean_search"  // search-time: 동의어 포함
      }
    }
  }
}
```

---

## 불용어 (stopwords_ko.txt)

```
# 조사, 접속사 등 검색에 불필요한 단어
그리고
그러나
하지만
그래서
또한
즉
```

> nori_part_of_speech 필터로 품사 기반 제거가 더 정확함. 불용어 파일은 보조적으로 사용.

---

## 자동완성 (Autocomplete)

### Edge N-gram 방식
```json
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "edge_ngram_tokenizer": {
          "type": "edge_ngram",
          "min_gram": 1,
          "max_gram": 20,
          "token_chars": ["letter", "digit"]
        }
      },
      "analyzer": {
        "autocomplete_index": {
          "type": "custom",
          "tokenizer": "edge_ngram_tokenizer",
          "filter": ["lowercase"]
        },
        "autocomplete_search": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "suggest": {
        "type": "text",
        "analyzer": "autocomplete_index",
        "search_analyzer": "autocomplete_search"
      }
    }
  }
}
```

### Completion Suggester (더 빠름)
```json
{
  "mappings": {
    "properties": {
      "suggest": {
        "type": "completion",
        "analyzer": "korean"
      }
    }
  }
}

// 쿼리
{
  "suggest": {
    "product-suggest": {
      "prefix": "삼성",
      "completion": { "field": "suggest", "size": 5 }
    }
  }
}
```

---

## 분석기 테스트

```json
// 토큰 분석 확인
POST /my-index/_analyze
{
  "analyzer": "korean",
  "text": "삼성전자 갤럭시 스마트폰 출시"
}

// 결과 예시
{
  "tokens": [
    { "token": "삼성전자", "position": 0 },
    { "token": "삼성", "position": 0 },
    { "token": "전자", "position": 1 },
    { "token": "갤럭시", "position": 2 },
    { "token": "스마트폰", "position": 3 },
    { "token": "출시", "position": 4 }
  ]
}
```

---

## 성능 팁

- `nori_part_of_speech`: 불필요한 품사 제거로 인덱스 크기 감소
- `nori_readingform`: 한자 → 한글 변환 (한자 포함 문서 검색 시)
- 사용자 사전은 최소한으로 (너무 많으면 토크나이저 성능 저하)
- 동의어는 search-time에 적용 (index 크기 절약 + 유연성)
