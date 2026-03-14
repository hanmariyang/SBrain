# SBrain — Second Brain

> 로컬 마크다운 파일을 **뇌 시각화**로 탐색하는 macOS 데스크탑 앱

노트를 **뉴런(Neuron)** 으로, 유사한 노트 간 연결을 **시냅스(Synapse)** 로 표현하여 실제 뇌 속을 탐색하는 듯한 경험을 제공합니다.

![macOS](https://img.shields.io/badge/macOS-14.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python)
![Django](https://img.shields.io/badge/Django-5.0-green?logo=django)

---

## Brain Metaphor

| 일반 용어 | SBrain 용어 | 설명 |
|----------|------------|------|
| 노트 | **Memory** (기억) | 하나의 마크다운 파일 |
| 청크 | **Neuron** (뉴런) | 파일을 분할한 텍스트 조각 + 임베딩 |
| 유사 연결 | **Synapse** (시냅스) | 임베딩 유사도 기반 노트 간 연결선 |
| 인덱싱 | **Memorize** (기억하기) | 폴더를 스캔하여 뇌에 기억 저장 |
| 검색 | **Recall** (회상) | 벡터 유사도 기반 기억 회상 |

## 주요 기능

- **Brain Map** — 다크 배경 위 뉴런 노드 + 시냅스 곡선 그래프. PCA 2D 투영으로 유사한 기억끼리 가까이 배치
- **Recall** — 벡터 유사도 기반 시맨틱 검색. 키워드가 아닌 의미로 검색
- **Folder Tree** — 로컬 폴더 구조 그대로 탐색. `.md` 파일 미리보기 지원
- **Markdown Viewer** — WKWebView 기반 마크다운 렌더러. 코드블록, 테이블, 체크박스, #태그 지원
- **Local-First** — 폴더 선택 즉시 로컬 그래프 생성. 백엔드 임베딩 완료 시 자동 업그레이드

## 기술 스택

```
┌─────────────────────────────────────────┐
│  SwiftUI macOS App (네이티브 다크 테마)    │
│  ┌────────┐ ┌──────────┐ ┌───────────┐  │
│  │BrainMap│ │ ListView │ │ MarkdownV │  │
│  └────┬───┘ └────┬─────┘ └─────┬─────┘  │
│       └──────────┴─────────────┘         │
│              APIClient                   │
│              (REST)                       │
├──────────────── ↕ ───────────────────────┤
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
# XcodeGen으로 프로젝트 생성 (선택)
cd app
xcodegen generate

# Xcode에서 빌드
open SBrain.xcodeproj
# Cmd + R 로 실행
```

앱이 실행되면 Django 백엔드가 자동으로 child process로 시작됩니다.

### 5. 사용법

1. 앱 실행 후 **폴더 열기** 버튼 클릭
2. 마크다운 파일이 있는 폴더 선택
3. 즉시 **폴더 구조 기반 Brain Map** 표시
4. 백그라운드에서 임베딩 생성 → 완료 시 **유사도 기반 Brain Map**으로 자동 업그레이드
5. 상단 검색바에서 **회상(Recall)** 으로 시맨틱 검색

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
│       ├── Models/             # Memory, Neuron, Synapse 모델
│       ├── Views/              # BrainMap, NoteList, NoteDetail
│       └── Services/           # API 통신, 상태 관리, 백엔드 프로세스
└── backend/                    # Django REST 백엔드
    ├── config/                 # Django 설정
    └── notes/                  # 핵심 로직
        ├── ingest.py           # MD 파싱 + 청크 + 임베딩
        ├── search.py           # 벡터 유사도 검색
        ├── graph.py            # PCA 2D 투영 + 코사인 유사도
        └── db.py               # sqlite-vec 연결
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

## 라이선스

MIT License
