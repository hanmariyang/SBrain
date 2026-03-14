# SBrain — Claude Code Instructions

## 1. 프로젝트 개요

로컬 마크다운/HTML 파일을 저장·인덱싱하고 **3D 뇌 시각화**로 탐색하는 macOS 데스크탑 앱.
노트를 **뉴런(Neuron)**으로, 유사한 노트 간 연결을 **시냅스(Synapse)**로 표현하여
실제 뇌 속을 탐색하는 듯한 경험을 제공.

**현재 버전: v0.2.0** — 멀티 프로젝트, 3D Sphere Brain Map, 프로젝트 필터링, HTML 지원

---

## 2. 문서 작성 정책 (Document Policy)

**모든 문서 작성 시 반드시 참조**
- `Docs/Global Policy/Document Type Policy.md` — 문서 유형 정의 (T1~T7)
- `Docs/Global Policy/Cursor Document Prompt Set.md` — 문서별 작성 양식

**절대 규칙**
- 문서 본문: 한국어
- 문서 제목(H1): 영문
- 파일명: snake_case (기술적 식별자, 제목과 무관)
- 하나의 문서 = 하나의 Type (T1~T7 혼합 금지)

**문서 메타데이터 (모든 문서 상단 필수)**
```
Type: T{N} – {Type Name}
Owner: gicheol
Status: Draft | In Progress | Done
Last Updated: YYYY-MM-DD
```

**문서 저장 경로**
```
Docs/
├── progress/              ← T1 (Overview/Summary), T6 (Execution Log)
├── Global Policy/         ← T5 (Policy/Rule) — 글로벌 정책만
└── v{X.Y.Z}/{feature}/   ← T2~T4, T7 (버전+기능별 하위 폴더)
```

---

## 3. 개발 요청 시 처음 2가지 (필수, 순서 고정)

개발 요청을 받으면 **코드 작성 전 반드시 아래 2가지를 먼저 실행**한다.

1. **브랜치 생성 및 전환**
   ```bash
   git checkout main && git pull
   git checkout -b v{X.Y.Z}/{descriptive-name}
   ```
2. **Docs 폴더 생성** — 버전/기능명과 동일한 이름으로 생성
   ```
   Docs/v{X.Y.Z}/{descriptive-name}/
   ```

---

## 4. 개발 요청 전 문서 작성 순서

브랜치·폴더 생성 후 아래 순서로 문서를 작성하고 개발한다.

1. **T2 — Background & Context**: 문제 정의 (왜 만드는가)
2. **T3 — Plan / Design**: 기획·설계 (무엇을, 어떻게)
3. **T4 — Specification**: API·데이터 명세 (구현 기준)
4. *(개발 진행)*
5. **T6 — Execution Log**: 이슈·트러블슈팅 기록
6. **T7 — Validation / Result**: 검증 결과
7. **T1 — Overview / Summary**: 전체 마무리 요약

> T2 없이 T3(설계)로 진행하지 않는다.

---

## 5. 커밋 메시지 규칙

```
{type}: {description}
```

| type | 사용 시점 |
|------|----------|
| feat | 새 기능 |
| fix | 버그 수정 |
| refactor | 리팩토링 (기능 변화 없음) |
| docs | 문서만 변경 |
| chore | 빌드·설정·패키지 |

---

## 6. 디자인 컨셉 — Brain Metaphor

| 일반 용어 | SBrain 용어 | 설명 |
|----------|------------|------|
| 노트 | **Memory (기억)** | 하나의 문서 파일 |
| 청크 | **Neuron (뉴런)** | 파일을 분할한 텍스트 조각 + 임베딩 |
| 유사 연결 | **Synapse (시냅스)** | 임베딩 유사도 기반 노트 간 연결선 |
| 인덱싱 | **Memorize (기억하기)** | 폴더를 스캔하여 뇌에 기억 저장 |
| 검색 | **Recall (회상)** | 벡터 유사도 기반 기억 회상 |

---

## 7. 기술 스택

- **macOS App**: SwiftUI (네이티브 macOS 앱, 다크 테마)
- **Backend**: Python 3.11 + Django 5 + Django REST Framework
- **Vector DB**: sqlite-vec (SQLite 확장)
- **Embedding**: Anthropic API (`voyage-3`)
- **Web (향후)**: React + Next.js — 동일 Django REST API 공유

---

## 8. 디렉토리 구조

```
SBrain/
├── CLAUDE.md
├── .gitignore
├── Docs/
│   ├── progress/                  # T1, T6
│   ├── Global Policy/             # T5 — 글로벌 정책만
│   │   ├── Document Type Policy.md
│   │   ├── Cursor Document Prompt Set.md
│   │   └── claude_skill_agent_plan.md
│   ├── v0.1.0/sbrain-mvp/        # T2~T4, T7 (MVP, superseded)
│   │   ├── sbrain_architecture_plan.md
│   │   └── sbrain_api_specification.md
│   └── v0.2.0/multi-project-3d/  # T3, T4 (현재)
│       ├── sbrain_v0.2.0_plan.md
│       └── sbrain_v0.2.0_specification.md
├── venv/                          # Python 3.11 가상환경
├── app/                           # SwiftUI macOS 앱
│   ├── project.yml                # XcodeGen 설정
│   ├── SBrain.xcodeproj
│   └── SBrain/
│       ├── SBrainApp.swift
│       ├── Models/
│       │   └── Note.swift
│       ├── Views/
│       │   ├── ContentView.swift
│       │   ├── BrainMapView.swift
│       │   ├── NoteListView.swift
│       │   └── NoteDetailView.swift
│       └── Services/
│           ├── APIClient.swift
│           ├── BackendManager.swift
│           ├── FolderScanner.swift
│           ├── LocalGraphBuilder.swift
│           └── NoteStore.swift
└── backend/                       # Python Django 백엔드
    ├── manage.py
    ├── requirements.txt
    ├── .env.example
    ├── config/
    │   ├── settings.py
    │   ├── urls.py
    │   └── wsgi.py
    └── notes/
        ├── models.py
        ├── serializers.py
        ├── views.py
        ├── urls.py
        ├── ingest.py
        ├── search.py
        ├── graph.py
        └── db.py
```

---

## 9. API 엔드포인트

```
POST /api/ingest/          { folder_path }          → 기억하기 시작
GET  /api/notes/           → Memory 목록
GET  /api/notes/{id}/      → Memory 상세
POST /api/search/          { query, limit }         → 회상 (벡터 검색)
GET  /api/status/          → 기억하기 진행 상태
GET  /api/graph/           ?threshold=0.5           → Brain Graph (뉴런 + 시냅스)
```

---

## 10. 환경 변수

```
ANTHROPIC_API_KEY=sk-ant-...
EMBEDDING_MODEL=voyage-3
DB_PATH=./brain.db
DJANGO_SECRET_KEY=...
DJANGO_DEBUG=True
PORT=8765
```

---

## 11. 주의사항

- SwiftUI 앱에서 `Process`로 Django 서버를 child process로 실행/종료 관리
- 임베딩 API 호출은 배치로 처리 (rate limit 대응)
- 대용량 파일(1MB+)은 청크 크기 조정 필요
- App Sandbox 비활성화 상태 (파일 시스템 + 로컬 서버 접근 필요)
- sqlite-vec 벡터 테이블은 raw SQL로 관리 (Django ORM 미지원)
- Brain Graph의 PCA는 자체 구현 (power iteration) — numpy 의존성 없음
- 멀티 프로젝트: 여러 폴더를 동시에 열어 통합 3D Brain Map 탐색 가능
- 3D 레이아웃: Fibonacci Sphere 분포 (피보나치 스파이럴, numpy 없음)
- Brain Map 렌더링: 단일 Canvas + TimelineView 30fps + 3D→2D 원근 투영
- 제스처: `.simultaneousGesture()` + `minimumDistance: 5`로 충돌 방지
- 줌: NSView `scrollWheel` 이벤트 직접 처리 (SwiftUI MagnificationGesture 대체)
