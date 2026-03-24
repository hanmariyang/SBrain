# Plan: SBrain v0.9.0 Cloud Sync & iOS Expansion

Type: T3 – Plan / Design
Owner: gicheol
Status: Draft
Last Updated: 2026-03-24

---

## 1. Goal

macOS의 로컬 파일 워크플로우를 **완전히 유지**하면서, 클라우드 동기화를 통해 **iOS에서 읽기/검색/3D Brain Map**을 사용할 수 있는 구조를 확립한다.

### 성공 기준
1. macOS에서 `.md` 파일 편집 → 5분 이내에 iPhone에서 변경 내용 확인 가능
2. iPhone에서 3D Brain Map 탐색 + 검색 (Recall) 동작
3. macOS가 꺼져 있어도 iPhone에서 마지막 동기화 시점의 노트 열람 가능
4. macOS의 기존 워크플로우 변경 없음 (로컬 파일 편집, 로컬 검색 그대로)
5. 백엔드 테스트 커버리지 70%+

---

## 2. Scope

### In Scope
- Railway Django의 PostgreSQL 전환
- macOS → Railway 자동 동기화 (변경분만 push)
- 유저 인증 (JWT)
- iOS 앱 MVP (읽기 전용 + 검색 + 3D Brain Map)
- 백엔드 테스트 인프라
- TelemetryDeck 분석 통합
- 랜딩 페이지 + 공개 준비

### Out of Scope
- iOS에서 파일 편집 (v1.0에서 검토)
- Android 앱 (웹 버전으로 대체 예정)
- 웹 버전 (v1.0+)
- 실시간 동기화 (WebSocket/SSE — 현재는 주기적 push)
- 멀티 유저 협업
- App Store 정식 출시 (TestFlight까지만)

---

## 3. User Scenarios

### Scenario 1: macOS에서 노트 편집 → iPhone에서 확인 (정상 흐름)
```
1. 사용자가 VS Code에서 ~/notes/meeting.md 편집 후 저장
2. FileMonitor가 파일 변경 감지 (1초 debounce)
3. NoteStore.handleFileChange() 호출
   → 로컬 Django에 partial_ingest (기존)
   → Railway에 sync push (신규)
4. Railway Django가 PostgreSQL에 Note.content 업데이트
5. 사용자가 iPhone에서 SBrain 열기
6. iPhone 앱이 Railway API 호출 → 최신 meeting.md 내용 표시
```

### Scenario 2: iPhone에서 3D Brain Map 탐색 (정상 흐름)
```
1. iPhone에서 SBrain 앱 실행
2. JWT 토큰으로 Railway API 인증
3. GET /api/graph/ → 뉴런/시냅스 데이터 수신
4. 3D Brain Map 렌더링 (터치 회전, 핀치 줌)
5. 뉴런 탭 → GET /api/notes/{id}/ → 노트 상세 표시
```

### Scenario 3: macOS 꺼진 상태에서 iPhone 사용 (정상 흐름)
```
1. macOS 종료 전에 마지막 sync push 완료 (앱 종료 시 자동)
2. iPhone에서 SBrain 열기
3. Railway PostgreSQL에서 데이터 로드 → 정상 동작
4. 최근 열어본 노트는 iOS 로컬 캐시에서 → 오프라인에서도 열람
```

### Scenario 4: 맥북 장시간 꺼짐 → 켤 때 일괄 동기화 (예외 흐름)
```
1. 맥북을 이틀 동안 안 켰음
2. 그 사이 Railway에는 이틀 전 데이터 유지
3. 맥북 켜서 SBrain 실행
4. BackendManager 시작 → 로컬 Django 실행
5. 전체 프로젝트 스캔 → 변경된 파일 감지
6. Railway에 일괄 sync push
7. iPhone 갱신됨
```

---

## 4. Design Principles

1. **파일은 절대 이동하지 않는다**: 원본은 맥북 로컬. Railway에는 content 텍스트만 미러링
2. **macOS는 독립적으로 동작한다**: Railway 접근 불가해도 macOS 앱은 100% 정상 동작
3. **iOS는 클라우드 의존**: Railway API가 유일한 데이터 소스 + 로컬 캐시로 오프라인 보완
4. **기존 API 최대 활용**: `/api/notes/`, `/api/graph/`, `/api/search/` 그대로 사용
5. **점진적 전환**: macOS 앱의 기존 코드 변경 최소화. 동기화 레이어만 추가

---

## 5. Structure / Flow

### 5.1 전체 아키텍처 (TO-BE)

```
┌─ macOS (원본, 기존과 동일) ────────────────────────────────┐
│                                                            │
│  사용자 편집 (.md 파일)                                     │
│       ↓                                                    │
│  FileMonitor (FSEvents) → 변경 감지                        │
│       ↓                                                    │
│  NoteStore.handleFileChange()                              │
│       ├──→ 로컬 Django (localhost:8765)  ← 기존 그대로     │
│       │       ↓                                            │
│       │    brain.db (로컬 SQLite)                          │
│       │       ↓                                            │
│       │    로컬 검색 / 그래프 / 뷰                         │
│       │                                                    │
│       └──→ SyncManager (신규)                              │
│               ↓                                            │
│            Railway API (변경분 push)                        │
└────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─ Railway (클라우드 미러) ──────────────────────────────────┐
│                                                            │
│  Django + PostgreSQL                                       │
│    ├── notes_note (content 포함)                           │
│    ├── notes_chunk (검색용 청크)                           │
│    ├── vec_chunks (임베딩 — 향후)                          │
│    └── auth_user (JWT 인증)                                │
│                                                            │
│  기존 API 그대로 제공:                                     │
│    GET  /api/notes/          → 노트 목록                   │
│    GET  /api/notes/{id}/     → 노트 상세                   │
│    POST /api/search/         → 검색                        │
│    GET  /api/graph/          → Brain Graph                 │
│                                                            │
│  신규 API:                                                 │
│    POST /api/sync/push/      → macOS → Railway 동기화     │
│    POST /api/auth/token/     → JWT 발급                    │
│    POST /api/auth/refresh/   → JWT 갱신                    │
└────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─ iOS (읽기 전용 클라이언트) ──────────────────────────────┐
│                                                            │
│  SwiftUI App                                               │
│    ├── APIClient → Railway API 호출                        │
│    ├── 노트 목록 / 상세 보기                               │
│    ├── 3D Brain Map (터치 제스처)                          │
│    ├── 검색 (Recall)                                       │
│    ├── Slack / Calendar 읽기                               │
│    └── 로컬 캐시 (Core Data 또는 파일 캐시)               │
│                                                            │
│  오프라인: 캐시된 노트 열람 가능                           │
│  온라인: Railway에서 최신 데이터 로드                      │
└────────────────────────────────────────────────────────────┘
```

### 5.2 동기화 흐름 (macOS → Railway)

```
FileMonitor 변경 감지
    ↓
handleFileChange()
    ├──→ 로컬 partial_ingest (기존)
    └──→ SyncManager.pushChanges(paths, deletedPaths)
              ↓
         POST /api/sync/push/
         {
           "api_key": "user-api-key",
           "notes": [
             {
               "id": "sha256hash",
               "path": "project-name/subdir/file.md",  ← 프로젝트 상대경로
               "filename": "file.md",
               "content": "# 파일 전체 내용...",
               "updated_at": "2026-03-24T10:00:00Z"
             }
           ],
           "deleted_ids": ["sha256hash1", "sha256hash2"]
         }
              ↓
         Railway Django:
           - Note.objects.update_or_create() (PostgreSQL)
           - Chunk 재생성
           - 삭제된 Note/Chunk 제거
              ↓
         Response: { "synced": 3, "deleted": 1 }
```

### 5.3 앱 초기화 시퀀스 (macOS, TO-BE)

```
SBrainApp.onAppear
  │
  ├── backendManager.start()  ← 로컬 Django (기존)
  │
  └── .onChange(of: isRunning)
        │
        ├── Phase 1: 프로젝트 복원 (기존)
        ├── Phase 2: 인증 상태 복원 (기존)
        ├── Phase 3: FileMonitor 시작 (기존)
        └── Phase 4: 초기 동기화 (신규)
              └── SyncManager.fullSync()
                    → 로컬 brain.db vs Railway 비교
                    → 변경분만 push
```

### 5.4 iOS 앱 구조

```
SBrainApp (iOS)
  │
  ├── AuthView (로그인/API Key 입력)
  │
  └── MainTabView (인증 후)
        ├── Tab 1: Brain Map (3D)
        │     └── 터치 회전, 핀치 줌, 탭 선택
        ├── Tab 2: Notes (목록 + 상세)
        │     ├── NavigationSplitView (iPad)
        │     └── NavigationStack (iPhone)
        ├── Tab 3: Search (Recall)
        │     └── 검색 바 + 결과 목록
        └── Tab 4: Settings
              ├── 연결 상태
              ├── 캐시 관리
              └── 로그아웃
```

---

## 6. Decision Points

### DP-1: 동기화 트리거 방식

| 선택지 | 장점 | 단점 |
|--------|------|------|
| **A. FileMonitor 연동 (실시간)** | 변경 즉시 push, 지연 최소 | 빈번한 API 호출 |
| B. 주기적 폴링 (5분) | 구현 간단, API 호출 적음 | 최대 5분 지연 |
| C. 수동 동기화 | 가장 간단 | UX 불편 |

**추천: A** — FileMonitor에 이미 1초 debounce 있음. 여기에 sync push만 추가하면 자연스러움

### DP-2: iOS 인증 방식

| 선택지 | 장점 | 단점 |
|--------|------|------|
| **A. API Key (단순)** | 구현 간단, macOS에서 생성→QR로 iOS 전달 | 토큰 갱신 없음 |
| B. JWT (access + refresh) | 업계 표준, 만료 관리 | 구현 복잡도 증가 |
| C. Sign in with Apple | Apple 생태계 통합 | 서버 검증 로직 필요 |

**추천: A (MVP)** → **B (정식 출시 시)** — MVP에서는 API Key로 빠르게, 나중에 JWT 전환

### DP-3: Railway DB 전환

| 선택지 | 장점 | 단점 |
|--------|------|------|
| **A. PostgreSQL (Railway 내장)** | Railway에서 원클릭 추가, Django 네이티브 | 마이그레이션 필요 |
| B. SQLite (Railway Volume) | 코드 변경 없음 | 동시 접속 제한, 성능 |
| C. Supabase (외부) | 풍부한 기능 | 추가 의존성, 비용 |

**추천: A** — Railway에서 PostgreSQL 추가는 무료, Django ORM이 자동으로 대응

### DP-4: iOS 3D 렌더링

| 선택지 | 장점 | 단점 |
|--------|------|------|
| **A. Canvas + TimelineView (현재 macOS 방식 포팅)** | 코드 공유 최대, 2D 투영 | 성능 한계 (수천 뉴런) |
| B. SceneKit | 네이티브 3D, 조명/물리 | 새로 구현 |
| C. Metal | 최고 성능 | 구현 복잡도 극도로 높음 |

**추천: A** — 현재 BrainMapView의 Canvas 코드가 SwiftUI 크로스플랫폼. 터치 제스처만 교체하면 iOS에서 동작

### DP-5: iOS 오프라인 캐시

| 선택지 | 장점 | 단점 |
|--------|------|------|
| **A. URLCache (HTTP 캐시)** | 구현 0줄, 자동 | 세밀한 제어 어려움 |
| B. Core Data | 쿼리 가능, 구조적 | 오버엔지니어링 |
| **C. 파일 캐시 (JSON)** | 구현 간단, 직관적 | 검색 불가 |

**추천: A + C 혼합** — API 응답은 URLCache 자동 캐시, 자주 보는 노트는 JSON 파일로 명시 저장

---

## 7. 구현 순서 (Sub-Phase)

| 순서 | Sub-Phase | 기간 | 내용 |
|------|-----------|------|------|
| 1 | **0-A: 백엔드 클라우드 전환** | 1~1.5주 | PostgreSQL, JWT 인증, sync push API |
| 2 | **0-B: macOS 동기화 레이어** | 1주 | SyncManager, FileMonitor 연동, 초기 sync |
| 3 | **0-C: 테스트 인프라** | 3~5일 | Backend pytest, CI 워크플로우 |
| 4 | **0-D: iOS MVP** | 1~1.5주 | 멀티타겟, Brain Map, 노트 뷰어, 검색 |
| 5 | **0-E: 관측성 + 공개** | 3~5일 | TelemetryDeck, 랜딩 페이지, README |

---

## 8. Open Issues

| # | 항목 | 상태 |
|---|------|------|
| 1 | Railway PostgreSQL 무료 티어 용량 제한 (500MB) — 충분한가? | 확인 필요 |
| 2 | 대용량 파일(1MB+) sync 시 API 요청 크기 제한 | 청크 분할 or 압축 검토 |
| 3 | macOS 앱 종료 시 미완료 sync 처리 (graceful shutdown) | 설계 필요 |
| 4 | iOS App Store 심사 — TestFlight 외부 테스트 승인 소요 시간 | 1~3일 예상 |
| 5 | TelemetryDeck 무료 티어 (10만 이벤트/월) 충분한가 | 베타 규모에서는 충분 |
| 6 | 기존 Railway 배포와 PostgreSQL 추가 시 환경변수 설정 | 배포 시 확인 |
