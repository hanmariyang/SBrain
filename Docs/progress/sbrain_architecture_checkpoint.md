# Overview: SBrain Architecture Checkpoint — Mid-Project Review

Type: T1 – Overview / Summary
Owner: gicheol
Status: In Progress
Last Updated: 2026-03-16

---

## 1. 프로젝트 현황

SBrain은 로컬 마크다운/HTML 파일과 외부 PostgreSQL 데이터베이스를 **3D 뇌 시각화**로 탐색하는 macOS 네이티브 앱이다.
노트를 **뉴런(Neuron)**, 유사 연결을 **시냅스(Synapse)**로 표현하여 실제 뇌 속을 탐색하는 경험을 제공한다.

| 항목 | 상태 |
|------|------|
| 현재 버전 | v0.3.0 (DB Browser + Hand Interaction 진행 중) |
| 완료 버전 | v0.1.0 (MVP), v0.2.0 (멀티 프로젝트 + 3D Sphere) |
| 핵심 기능 | 노트 인덱싱, 3D Brain Map, DB 브라우저, 핸드 트래킹 |
| 배포 형태 | macOS 앱 + Docker Compose (백엔드 3개 서비스) |

---

## 2. 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    macOS App (SwiftUI)                       │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌─────────────┐  ┌─────────┐ │
│  │ BrainMap │  │ NoteList │  │ DB Browser  │  │  Hand   │ │
│  │  View    │  │  View    │  │    View     │  │ Overlay │ │
│  └────┬─────┘  └────┬─────┘  └──────┬──────┘  └────┬────┘ │
│       │              │               │              │       │
│  ┌────┴──────────────┴───────────────┴──────────────┴────┐  │
│  │              State Management Layer                    │  │
│  │  NoteStore  │  DatabaseStore  │  HandTrackingManager  │  │
│  └────────────────────┬──────────────────────────────────┘  │
│                       │                                     │
│  ┌────────────────────┴──────────────────────────────────┐  │
│  │           APIClient (HTTP → localhost:8765)            │  │
│  └────────────────────┬──────────────────────────────────┘  │
│                       │                                     │
│  ┌────────────────────┴──────────────────────────────────┐  │
│  │  BackendManager (Docker 감지 / 로컬 Django fallback)  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTP :8765
┌─────────────────────────┴───────────────────────────────────┐
│                Docker Compose Infrastructure                 │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │         Django REST API (backend)                    │    │
│  │  notes/views.py — 16 endpoints                      │    │
│  │  ┌──────────┐ ┌──────────┐ ┌───────────────────┐   │    │
│  │  │  ingest  │ │  search  │ │   db_browser      │   │    │
│  │  │  .py     │ │  .py     │ │   db_mirror.py    │   │    │
│  │  └────┬─────┘ └────┬─────┘ └────────┬──────────┘   │    │
│  │       │             │                │              │    │
│  │  ┌────┴─────┐  ┌───┴────┐   ┌───────┴──────────┐   │    │
│  │  │ SQLite + │  │ TF-IDF │   │ psycopg2         │   │    │
│  │  │sqlite-vec│  │ (local)│   │ (PostgreSQL 접속) │   │    │
│  │  └──────────┘  └────────┘   └───────┬──────────┘   │    │
│  └─────────────────────────────────────┼───────────────┘    │
│                                        │                    │
│  ┌──────────────┐    ┌─────────────────┴──────────────┐     │
│  │  cache-db    │    │      외부 PostgreSQL            │     │
│  │  :5434       │    │  (로컬 5432 / Railway 등)       │     │
│  │  (미러 저장) │    └────────────────────────────────┘     │
│  └──────────────┘                                           │
│  ┌──────────────┐                                           │
│  │  sample-db   │                                           │
│  │  :5435       │                                           │
│  │  (테스트용)  │                                           │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 기술 스택

### 3.1 프론트엔드 (macOS App)

| 기술 | 용도 | 비고 |
|------|------|------|
| SwiftUI | UI 프레임워크 | macOS 네이티브, 다크 테마 |
| Combine | 상태 관리 | @Published + @StateObject |
| Canvas + TimelineView | 3D Brain Map 렌더링 | 30fps, 원근 투영 |
| WebKit (WKWebView) | 노트 렌더링 | Markdown → HTML 변환 |
| Vision.framework | 핸드 트래킹 | 제스처 인식 (포인트, 핀치, 빅토리) |
| AVFoundation | 카메라 입력 | 핸드 포즈 감지용 |

### 3.2 백엔드 (Django REST API)

| 기술 | 용도 | 비고 |
|------|------|------|
| Python 3.11 | 런타임 | Docker 내 실행 |
| Django 5 + DRF | REST API | 16개 엔드포인트 |
| SQLite + sqlite-vec | 벡터 DB | 1024차원 임베딩 저장 |
| psycopg2 | PostgreSQL 접속 | DB 브라우저 + 미러링 |
| TF-IDF (자체 구현) | 키워드 검색 | 외부 API 의존 없음 |
| PCA (자체 구현) | 그래프 레이아웃 | power iteration, numpy 없음 |

### 3.3 인프라 (Docker Compose)

| 서비스 | 이미지 | 포트 | 용도 |
|--------|--------|------|------|
| backend | python:3.11-slim | 127.0.0.1:8765 | Django REST API |
| cache-db | postgres:16-alpine | 5434 | DB 미러 저장소 |
| sample-db | postgres:16-alpine | 5435 | 테스트용 샘플 DB (10 테이블) |

---

## 4. 모듈 구성

### 4.1 Swift 앱 (app/SBrain/)

```
SBrain/
├── SBrainApp.swift              ← @main 진입점, 4개 StateObject 초기화
├── Models/
│   └── Note.swift               ← 전체 도메인 모델 (17개 타입)
├── Views/
│   ├── ContentView.swift        ← 메인 레이아웃 (HSplitView, 뷰 라우팅)
│   ├── BrainMapView.swift       ← 3D 뇌 시각화 (Canvas, 회전, 줌)
│   ├── NoteListView.swift       ← 폴더 트리 + 검색 결과
│   ├── NoteDetailView.swift     ← 노트 콘텐츠 (WKWebView)
│   ├── DatabaseBrowserView.swift ← PostgreSQL 탐색기
│   └── HandCursorOverlay.swift  ← 핸드 제스처 시각화
└── Services/
    ├── BackendManager.swift     ← Django 프로세스 관리 (Docker/로컬)
    ├── APIClient.swift          ← HTTP 클라이언트 (16개 API 호출)
    ├── NoteStore.swift          ← 노트/프로젝트 상태 관리
    ├── DatabaseStore.swift      ← DB 연결/스키마/테이블 상태 관리
    ├── FolderScanner.swift      ← 로컬 파일시스템 스캔
    ├── LocalGraphBuilder.swift  ← 3D 뉴런 배치 (Fibonacci Sphere)
    └── HandTrackingManager.swift ← Vision 핸드 포즈 감지
```

### 4.2 Django 백엔드 (backend/notes/)

```
notes/
├── views.py          ← 16개 REST 엔드포인트
├── urls.py           ← URL 라우팅
├── models.py         ← ORM 모델 (Note, Chunk)
├── serializers.py    ← DRF 직렬화
├── ingest.py         ← 파일 스캔 → 청킹 → 저장 (백그라운드)
├── search.py         ← TF-IDF 키워드 검색
├── graph.py          ← PCA 투영 + 시냅스 생성
├── db.py             ← sqlite-vec 초기화
├── db_browser.py     ← PostgreSQL 인트로스펙션 (스키마, 테이블, 행)
└── db_mirror.py      ← DB 미러링 (pg_dump | gzip → gunzip | psql)
```

---

## 5. 데이터 흐름

### 5.1 노트 인덱싱 (Memorize)

```
사용자: 폴더 선택
  → FolderScanner: 로컬 트리 구축 (.md, .html, .htm)
  → APIClient.memorize(folderPath)
  → POST /api/ingest/
  → ingest.py: 백그라운드 스레드
    → 파일 스캔 → 500자 청크 (50자 오버랩) → Note/Chunk 저장
  → 앱: 10초 간격 /api/status/ 폴링
  → 완료 시: Brain Graph 로드
```

### 5.2 검색 (Recall)

```
사용자: 검색어 입력
  → APIClient.recall(query)
  → POST /api/search/
  → search.py: TF-IDF 로컬 검색 (외부 API 없음)
  → 결과: [{noteId, filename, chunkText, score}]
```

### 5.3 3D Brain Map

```
GET /api/graph/?threshold=0.5
  → graph.py: sqlite-vec에서 임베딩 로드
    → PCA 2D 투영 (power iteration)
    → 유사도 기반 시냅스 생성
  → 앱: LocalGraphBuilder
    → Fibonacci Sphere 3D 배치
    → 프로젝트별 영역 할당
  → BrainMapView: Canvas 렌더링 (30fps)
    → 3D→2D 원근 투영
    → 드래그 회전, 스크롤 줌
```

### 5.4 DB 브라우저

```
사용자: PostgreSQL URL 입력
  → POST /api/db/connect/ → 연결 테스트
  → GET /api/db/schemas/ → 스키마 목록
  → GET /api/db/tables/ → 테이블 목록 (row estimate 포함)
  → GET /api/db/columns/ → 컬럼 메타데이터
  → GET /api/db/rows/?limit=200&offset=0 → 페이지네이션 데이터
  → GET /api/db/graph/ → DB 테이블을 뉴런으로 시각화
```

### 5.5 DB 미러링 (Download)

```
사용자: 다운로드 버튼 클릭
  → POST /api/db/download/ → 백그라운드 스레드 시작
  → db_mirror.py:
    1. DROP/CREATE 로컬 미러 DB (cache-db)
    2. pg_dump (원격) | gzip → 압축 파일
    3. gunzip | psql → 로컬 cache-db 복원
    4. 검증 (테이블 수 확인)
  → 앱: 2초 간격 GET /api/db/download/status/ 폴링
    → 진행률 표시 (MB, 속도, 경과 시간)
    → 5회 연속 실패 시 자동 중단
```

### 5.6 로컬 DB 직접 접속

```
사용자: postgresql://user:pass@localhost:5432/dbname 입력
  → Docker 내부 자동 변환: localhost → host.docker.internal
  → 다운로드 없이 직접 쿼리 (읽기 전용)
  → 로컬 미러가 있으면 미러 우선 사용
```

---

## 6. API 엔드포인트 (16개)

### 6.1 노트 관리

| Method | Endpoint | 설명 |
|--------|----------|------|
| POST | /api/ingest/ | 폴더 인덱싱 시작 |
| GET | /api/notes/ | Memory 목록 |
| GET | /api/notes/{id}/ | Memory 상세 |
| POST | /api/search/ | 키워드 검색 (TF-IDF) |
| GET | /api/status/ | 인덱싱 진행 상태 |
| GET | /api/graph/ | Brain Graph (뉴런 + 시냅스) |

### 6.2 DB 브라우저

| Method | Endpoint | 설명 |
|--------|----------|------|
| POST | /api/db/connect/ | PostgreSQL 연결 테스트 |
| GET | /api/db/schemas/ | 스키마 목록 |
| GET | /api/db/tables/ | 테이블 목록 |
| GET | /api/db/columns/ | 컬럼 메타데이터 |
| GET | /api/db/rows/ | 행 데이터 (페이지네이션) |
| POST | /api/db/search/ | DB 전체 텍스트 검색 |
| GET | /api/db/graph/ | DB 테이블 → Brain Graph |

### 6.3 DB 미러링

| Method | Endpoint | 설명 |
|--------|----------|------|
| POST | /api/db/download/ | 미러 다운로드 시작 |
| GET | /api/db/download/status/ | 다운로드 진행 상태 |
| POST | /api/db/mirror/delete/ | 로컬 미러 삭제 |

---

## 7. 주요 설계 결정

### DD1: 로컬 우선 검색 (TF-IDF)

벡터 검색(Anthropic voyage-3) 대신 자체 TF-IDF 구현을 기본 검색으로 사용.
- **이유**: 외부 API 의존도 최소화, 오프라인 동작, 비용 절감
- **트레이드오프**: 의미 기반 검색 품질은 벡터 검색보다 낮음

### DD2: pg_dump | gzip 파이프라인

DB 미러링에 `pg_dump --format=custom` + `pg_restore` 대신 plain SQL + gzip 파이프라인 사용.
- **이유**: 더 빠르고, 메모리 효율적이며, 디버깅 용이
- **패턴**: `pg_dump | gzip > file.sql.gz` → `gunzip -c | psql`

### DD3: Docker 감지 + 로컬 fallback

BackendManager가 Docker 백엔드를 자동 감지하고, 없으면 로컬 Django를 시작.
- **이유**: Docker 없이도 개발/테스트 가능
- **주의**: 포트 충돌 방지를 위해 시작 시 고아 프로세스 정리 필요

### DD4: localhost → host.docker.internal 자동 변환

Docker 내부에서 사용자가 입력한 `localhost:PORT`를 자동으로 `host.docker.internal:PORT`로 변환.
- **이유**: 사용자가 Docker 네트워킹을 의식하지 않아도 됨
- **포트 매핑**: 5435 → sample-db:5432, 5434 → cache-db:5432, 기타 → host.docker.internal

### DD5: 3D 레이아웃 — Fibonacci Sphere

뉴런 배치에 Fibonacci Spiral 기반 Sphere 분포 사용.
- **이유**: 균일 분포, numpy 의존 없음, 멀티 프로젝트 영역 할당 용이
- **렌더링**: Canvas + TimelineView 30fps + 3D→2D 원근 투영

---

## 8. 버전 이력

| 버전 | 핵심 기능 | 상태 |
|------|----------|------|
| v0.1.0 | MVP — 노트 인덱싱, 검색, 2D 그래프 | Done |
| v0.2.0 | 멀티 프로젝트, 3D Sphere Brain Map, HTML 지원 | Done |
| v0.3.0 | DB 브라우저, DB Brain Map, 핸드 인터랙션, DB 미러링 | In Progress |

---

## 9. 파일 규모

| 영역 | 파일 수 | 주요 파일 크기 |
|------|---------|---------------|
| Swift Views | 6 | BrainMapView (796줄), DatabaseBrowserView (946줄), ContentView (487줄) |
| Swift Services | 7 | HandTrackingManager (581줄), NoteStore (349줄), DatabaseStore (298줄) |
| Swift Models | 1 | Note.swift (266줄, 17개 타입 정의) |
| Python 백엔드 | 10 | db_browser.py (397줄), db_mirror.py (299줄), views.py (200줄) |
| Docker | 3 서비스 | docker-compose.yml, Dockerfile, init.sql |

---

## 10. 현재 이슈 및 기술 부채

### 해결된 이슈

- [x] Docker 네트워킹 — localhost 리라이트 구현
- [x] pg_dump 메모리 문제 — temp file + gzip 파이프라인으로 전환
- [x] 무한 스피너 — poll 에러 카운터 + 자동 중단
- [x] 포트 충돌 — 고아 프로세스 정리 + IPv4 바인딩 명시
- [x] DB 테이블 뷰 레이아웃 — 고정 헤더 + 스크롤 분리

### 알려진 이슈

- [ ] 대용량 DB 미러링 (1.5GB+) — 시간 소요가 큼, 로컬 직접 접속 권장
- [ ] 테스트 코드 없음 — backend/notes/tests.py 비어있음
- [ ] 임베딩 API 미연동 — TF-IDF만 사용 중 (voyage-3 설정은 있음)
- [ ] App Sandbox 비활성화 — 파일시스템 + 로컬 서버 접근 필요

---

## 11. 다음 단계

1. v0.3.0 완료: DB 브라우저 안정화, 핸드 인터랙션 마무리
2. 임베딩 연동: voyage-3 API 호출 → sqlite-vec 저장 → 시맨틱 검색 활성화
3. 테스트 작성: 백엔드 API + DB 미러링 핵심 경로
4. 성능 최적화: 대규모 Brain Map 렌더링 (1000+ 뉴런)
