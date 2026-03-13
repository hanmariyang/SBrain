# SBrain — Second Brain MVP

## 프로젝트 개요
로컬 마크다운 파일을 저장·인덱싱하고 **뇌 시각화**로 탐색하는 macOS 데스크탑 앱.
노트를 **뉴런(Neuron)**으로, 유사한 노트 간 연결을 **시냅스(Synapse)**로 표현하여
실제 뇌 속을 탐색하는 듯한 경험을 제공.

## 디자인 컨셉 — Brain Metaphor
| 일반 용어 | SBrain 용어 | 설명 |
|----------|------------|------|
| 노트 | **Memory (기억)** | 하나의 마크다운 파일 |
| 청크 | **Neuron (뉴런)** | 파일을 분할한 텍스트 조각 + 임베딩 |
| 유사 연결 | **Synapse (시냅스)** | 임베딩 유사도 기반 노트 간 연결선 |
| 인덱싱 | **Memorize (기억하기)** | 폴더를 스캔하여 뇌에 기억 저장 |
| 검색 | **Recall (회상)** | 벡터 유사도 기반 기억 회상 |

## UI 구조
- **Brain Map (기본 뷰)** — 다크 배경 위 뉴런 노드 + 시냅스 곡선 그래프. PCA 2D 투영으로 배치, 유사한 기억끼리 가까이 위치. 노드는 글로우 효과 + 펄스 애니메이션.
- **List View (대체 뷰)** — 기존 목록 형태. 상단 토글로 전환.
- **Memory Detail (우측 패널)** — 선택한 기억의 마크다운 내용 렌더링.
- **Recall Bar (상단)** — 회상(검색) 입력.
- **Memorize Progress** — 기억 저장 중 뇌 활성화 애니메이션.

## 기술 스택
- **macOS App**: SwiftUI (네이티브 macOS 앱, 다크 테마)
- **Backend**: Python 3.11 + Django 5 + Django REST Framework
- **Vector DB**: sqlite-vec (SQLite 확장)
- **Embedding**: Anthropic API (`voyage-3`)
- **Web (향후)**: React + Next.js — 동일 Django REST API 공유

## 디렉토리 구조
```
SBrain/
├── CLAUDE.md
├── .gitignore
├── venv/                       # Python 3.11 가상환경
├── app/                        # SwiftUI macOS 앱
│   ├── project.yml             # XcodeGen 설정
│   ├── SBrain.xcodeproj
│   └── SBrain/
│       ├── SBrainApp.swift
│       ├── Models/
│       │   └── Note.swift          # Memory, Neuron, Synapse, BrainGraph 모델
│       ├── Views/
│       │   ├── ContentView.swift   # 메인 레이아웃 + TopBar + RecallBar
│       │   ├── BrainMapView.swift  # 뇌 그래프 시각화 (핵심 뷰)
│       │   ├── NoteListView.swift  # Memory 목록 + Recall 결과
│       │   └── NoteDetailView.swift# 기억 상세 + 마크다운 뷰어
│       └── Services/
│           ├── APIClient.swift     # Django REST API 통신
│           ├── BackendManager.swift# 백엔드 프로세스 관리
│           └── NoteStore.swift     # 상태 관리 (ObservableObject)
└── backend/                    # Python Django 백엔드
    ├── manage.py
    ├── requirements.txt
    ├── .env.example
    ├── config/
    │   ├── settings.py
    │   ├── urls.py
    │   └── wsgi.py
    └── notes/
        ├── models.py           # Note, Chunk ORM 모델
        ├── serializers.py      # DRF Serializer
        ├── views.py            # API View
        ├── urls.py             # 엔드포인트 라우팅
        ├── ingest.py           # MD 파싱 + 청크 + 임베딩
        ├── search.py           # 벡터 유사도 검색
        ├── graph.py            # Brain Graph (PCA + 코사인 유사도)
        └── db.py               # sqlite-vec 연결
```

## API 엔드포인트

```
POST /api/ingest/          { folder_path }          → 기억하기 시작
GET  /api/notes/           → Memory 목록
GET  /api/notes/{id}/      → Memory 상세
POST /api/search/          { query, limit }         → 회상 (벡터 검색)
GET  /api/status/          → 기억하기 진행 상태
GET  /api/graph/           ?threshold=0.5           → Brain Graph (뉴런 + 시냅스)
```

## 환경 변수
```
ANTHROPIC_API_KEY=sk-ant-...
EMBEDDING_MODEL=voyage-3
DB_PATH=./brain.db
DJANGO_SECRET_KEY=...
DJANGO_DEBUG=True
PORT=8765
```

## 주의사항
- SwiftUI 앱에서 `Process`로 Django 서버를 child process로 실행/종료 관리
- 임베딩 API 호출은 배치로 처리 (rate limit 대응)
- 대용량 파일(1MB+)은 청크 크기 조정 필요
- App Sandbox 비활성화 상태 (파일 시스템 + 로컬 서버 접근 필요)
- sqlite-vec 벡터 테이블은 raw SQL로 관리 (Django ORM 미지원)
- Brain Graph의 PCA는 자체 구현 (power iteration) — numpy 의존성 없음
