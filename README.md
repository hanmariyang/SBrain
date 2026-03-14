# SBrain — Second Brain

> 로컬 마크다운/HTML 파일을 **3D 뇌 시각화**로 탐색하는 macOS 데스크탑 앱

노트를 **뉴런(Neuron)** 으로, 유사한 노트 간 연결을 **시냅스(Synapse)** 로 표현하여 실제 뇌 속을 탐색하는 듯한 경험을 제공합니다.

![macOS](https://img.shields.io/badge/macOS-14.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python)
![Django](https://img.shields.io/badge/Django-5.0-green?logo=django)

---

## Brain Metaphor

| 일반 용어 | SBrain 용어 | 설명 |
|----------|------------|------|
| 노트 | **Memory** (기억) | 하나의 마크다운/HTML 파일 |
| 청크 | **Neuron** (뉴런) | 파일을 분할한 텍스트 조각 + 임베딩 |
| 유사 연결 | **Synapse** (시냅스) | 임베딩 유사도 기반 노트 간 연결선 |
| 인덱싱 | **Memorize** (기억하기) | 폴더를 스캔하여 뇌에 기억 저장 |
| 검색 | **Recall** (회상) | 벡터 유사도 기반 기억 회상 |

## 주요 기능

- **3D Brain Map** — 뉴런이 3D 구체(Sphere) 위에 분포. 자동 회전 + 드래그 회전 + 줌. 원근감으로 깊이 표현
- **멀티 프로젝트** — 여러 프로젝트 폴더를 동시에 추가·탐색. 프로젝트 탭으로 필터링
- **MD/HTML 지원** — Markdown은 원형(시안), HTML은 사각형(오렌지)으로 시각 구분
- **Recall** — 벡터 유사도 기반 시맨틱 검색. 키워드가 아닌 의미로 검색
- **Folder Tree** — 로컬 폴더 구조 그대로 탐색. 프로젝트별 섹션 분리
- **Document Viewer** — WKWebView 기반. Markdown 렌더링 + HTML 직접 표시
- **Local-First** — 폴더 선택 즉시 3D 그래프 생성. 백엔드 임베딩 완료 시 자동 업그레이드

## 기술 스택

```
┌─────────────────────────────────────────┐
│  SwiftUI macOS App (네이티브 다크 테마)    │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐  │
│  │ 3D Brain │ │ ListView │ │ Viewer  │  │
│  │   Map    │ │ (Tree)   │ │ MD/HTML │  │
│  └────┬─────┘ └────┬─────┘ └────┬────┘  │
│       └─────────────┴────────────┘       │
│           NoteStore (State)              │
│           APIClient (REST)               │
├──────────────── ↕ ──────────────────────┤
│  Django 5 + DRF Backend                  │
│  ┌────────┐ ┌────────┐ ┌──────────────┐ │
│  │ Ingest │ │ Search │ │  Graph (PCA) │ │
│  └────┬───┘ └───┬────┘ └──────┬───────┘ │
│       └─────────┴──────────────┘         │
│     sqlite-vec     Anthropic API         │
│     (Vector DB)    (voyage-3)            │
└─────────────────────────────────────────┘
```

## 시작하기

### 사전 요구사항

- macOS 14.0+
- Xcode 15+
- Python 3.11
- [Anthropic API Key](https://console.anthropic.com/)

### 1. 저장소 클론

```bash
git clone https://github.com/your-username/SBrain.git
cd SBrain
```

### 2. 백엔드 설정

```bash
# 가상환경 생성 & 활성화
python3.11 -m venv venv
source venv/bin/activate

# 의존성 설치
pip install -r backend/requirements.txt

# 환경 변수 설정
cp backend/.env.example backend/.env
# backend/.env 파일을 열어 ANTHROPIC_API_KEY 입력
```

### 3. 데이터베이스 초기화

```bash
cd backend
python manage.py migrate
cd ..
```

### 4. 앱 빌드 & 실행

```bash
cd app
open SBrain.xcodeproj
# Cmd + R 로 실행
```

앱이 실행되면 Django 백엔드가 자동으로 child process로 시작됩니다.

### 5. 사용법

1. 앱 실행 후 **프로젝트 추가** 버튼 클릭 (복수 선택 가능)
2. MD/HTML 파일이 있는 폴더 선택
3. 즉시 **3D Brain Map** 표시 — 드래그로 회전, 스크롤로 줌
4. 상단 프로젝트 탭으로 필터링 (All / 개별 프로젝트)
5. 뉴런 클릭 → 우측 패널에서 문서 상세 보기
6. 상단 검색바에서 **회상(Recall)** 으로 시맨틱 검색

## API 엔드포인트

| Method | Endpoint | 설명 |
|--------|----------|------|
| `POST` | `/api/ingest/` | 폴더 기억하기 (임베딩 생성) |
| `GET` | `/api/notes/` | Memory 목록 |
| `GET` | `/api/notes/{id}/` | Memory 상세 |
| `POST` | `/api/search/` | 회상 (벡터 검색) |
| `GET` | `/api/status/` | 기억하기 진행 상태 |
| `GET` | `/api/graph/?threshold=0.5` | Brain Graph (뉴런 + 시냅스) |

## 프로젝트 구조

```
SBrain/
├── app/                        # SwiftUI macOS 앱
│   ├── project.yml             # XcodeGen 설정
│   └── SBrain/
│       ├── SBrainApp.swift     # 앱 진입점
│       ├── Models/
│       │   └── Note.swift      # Memory, Neuron (3D), Synapse, BrainGraph
│       ├── Views/
│       │   ├── ContentView.swift    # 메인 레이아웃 + ProjectTabBar
│       │   ├── BrainMapView.swift   # 3D 뇌 시각화 (핵심 뷰)
│       │   ├── NoteListView.swift   # 폴더 트리 + Recall 결과
│       │   └── NoteDetailView.swift # MD/HTML 뷰어
│       └── Services/
│           ├── APIClient.swift          # Django REST API 통신
│           ├── BackendManager.swift     # 백엔드 프로세스 관리
│           ├── NoteStore.swift          # 상태 관리 (멀티 프로젝트)
│           ├── LocalGraphBuilder.swift  # 3D Fibonacci Sphere 레이아웃
│           └── FolderScanner.swift      # 파일 스캔 (MD/HTML)
├── backend/                    # Django REST 백엔드
│   ├── config/                 # Django 설정
│   └── notes/                  # 핵심 로직 (ingest, search, graph)
└── Docs/                       # T-type 문서 체계
    ├── Global Policy/          # T5 정책 문서
    ├── v0.1.0/                 # MVP 설계/명세
    └── v0.2.0/                 # 멀티 프로젝트 + 3D
```

## 환경 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `ANTHROPIC_API_KEY` | Anthropic API 키 | (필수) |
| `EMBEDDING_MODEL` | 임베딩 모델 | `voyage-3` |
| `DB_PATH` | 데이터베이스 경로 | `./brain.db` |
| `DJANGO_SECRET_KEY` | Django 시크릿 키 | (필수) |
| `DJANGO_DEBUG` | 디버그 모드 | `True` |
| `PORT` | 백엔드 포트 | `8765` |

## 버전 히스토리

| Version | Description |
|---------|-------------|
| v0.1.0 | MVP — 단일 폴더, 2D Brain Map, MD 뷰어 |
| v0.2.0 | 멀티 프로젝트, 3D Sphere Brain Map, HTML 지원, 프로젝트 필터링 |

## 라이선스

MIT License
