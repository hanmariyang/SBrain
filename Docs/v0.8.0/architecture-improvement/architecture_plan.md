# Plan: SBrain v0.8.0 Architecture Improvement

Type: T3 – Plan / Design
Owner: gicheol
Status: Draft
Last Updated: 2026-03-24

---

## 1. Goal

SBrain의 **상태 영속화**와 **이벤트 기반 반응성**을 개선하여, 앱 재시작 시 인증이 유지되고 파일 변경이 실시간 반영되는 구조를 확립한다.

### 성공 기준
1. 앱 재시작 후 Google Calendar / Slack 재인증 없이 즉시 사용 가능
2. 프로젝트 폴더 내 파일 추가/수정/삭제가 3초 이내에 사이드바 트리에 반영
3. 변경된 파일만 부분 재인덱싱되어 Brain Graph에 자동 반영

---

## 2. Scope

### In Scope
- Slack `user_id` 및 인증 상태 영구 저장
- Google Calendar 토큰 복원 로직 안정화
- SwiftUI 앱 초기화 시퀀스 개선 (백엔드 ready 기반)
- macOS FSEvents 기반 파일 시스템 모니터링
- 변경분 부분 재인덱싱 API
- 인메모리 Slack 상태의 SQLite 영속화

### Out of Scope
- WebSocket/SSE 기반 백엔드↔프론트엔드 실시간 통신 (향후 v0.9.0)
- Keychain 기반 시크릿 관리 (보안 강화는 별도 이터레이션)
- 멀티 유저 인증 체계

---

## 3. User Scenarios

### Scenario 1: 앱 재시작 후 정상 복원 (정상 흐름)
```
1. 사용자가 SBrain 앱을 종료한다.
2. 다시 앱을 실행한다.
3. BackendManager가 Django 서버를 시작한다.
4. 백엔드가 저장된 인증 정보를 자동 로드한다:
   - .google_tokens.json → Google Calendar 토큰 복원
   - .slack_user.json → Slack user_id 복원
   - slack_state.db → Slack 메시지/처리 ID 복원
5. 백엔드 health check 성공 (isRunning = true)
6. SwiftUI가 onChange(of: isRunning)에서 인증 상태 확인
7. SlackStore, CalendarStore가 "인증됨" 상태로 표시
8. 사용자는 재인증 없이 바로 사용 가능
```

### Scenario 2: 파일 변경 실시간 반영 (정상 흐름)
```
1. 사용자가 VS Code에서 프로젝트 폴더의 .md 파일을 수정한다.
2. FileMonitor(FSEvents)가 변경 이벤트를 감지한다.
3. 1초 debounce 후 NoteStore.handleFileChange() 호출
4. FolderScanner가 변경된 경로만 부분 리스캔
5. @Published projects 업데이트 → 사이드바 트리 즉시 갱신
6. 백엔드에 변경 파일 재인덱싱 요청 (PATCH /api/ingest/)
7. 인덱싱 완료 후 Brain Graph 자동 리빌드
```

### Scenario 3: Google 토큰 만료 (예외 흐름)
```
1. 앱 시작 시 .google_tokens.json에서 토큰 로드
2. access_token 만료 → refresh_token으로 자동 갱신 시도
3-a. 갱신 성공 → 정상 진행
3-b. refresh_token도 만료/취소 → API가 re_auth_required: true 반환
4. SwiftUI가 "Google Calendar 재인증 필요" 배너 표시
5. 사용자가 재인증 버튼 클릭 → OAuth 플로우 진행
```

---

## 4. Design Principles

1. **백엔드 Ready 기반 초기화**: 하드코딩 딜레이(2초) 대신, `isRunning` 상태 변화를 감지하여 순차적으로 초기화
2. **영속화 우선**: 인메모리 상태는 반드시 디스크에 백업. 프로세스 재시작 시 복원 가능
3. **이벤트 기반 갱신**: 폴링 대신 FSEvents 기반 파일 감시. 변경 시점에만 리소스 사용
4. **최소 변경 원칙**: 기존 아키텍처를 최대한 유지하면서 영속화 레이어만 추가
5. **부분 갱신**: 전체 리스캔/재인덱싱 대신 변경분만 처리하여 성능 유지

---

## 5. Structure / Flow

### 5.1 AS-IS Architecture

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI App                       │
│                                                      │
│  SBrainApp.swift                                    │
│    ├── BackendManager  ──start()──→ Django Process   │
│    ├── NoteStore       ──2s delay──→ restoreProjects │
│    ├── SlackStore      ──poll──→ /api/slack/status/  │
│    └── CalendarStore   ──poll──→ /api/calendar/status│
│                                                      │
│  FolderScanner                                      │
│    └── scan(at:) ← 1회성, FSEvents 없음             │
│                                                      │
│  인증 상태: 자체 저장 없음, 백엔드 폴링 의존         │
└─────────────────────────────────────────────────────┘
                        │ HTTP
┌─────────────────────────────────────────────────────┐
│                   Django Backend                     │
│                                                      │
│  Slack State (인메모리):                             │
│    _messages: list[dict]        ← 재시작 시 소실     │
│    _processed_ids: set[str]     ← 재시작 시 소실     │
│    _filter_settings["user_id"]  ← 재시작 시 소실     │
│                                                      │
│  Google State:                                       │
│    .google_tokens.json          ← 파일, 유지됨       │
│    (refresh 실패 시 에러 처리 미흡)                   │
│                                                      │
│  Ingest: POST /api/ingest/ ← 1회성, 변경 감지 없음  │
└─────────────────────────────────────────────────────┘
```

**AS-IS 문제점 요약**:
- 인증 상태: Slack 인메모리 소실, 앱 측 캐시 없음
- 파일 감시: 없음 (1회성 스캔)
- 초기화 순서: 2초 하드코딩 딜레이, race condition 가능
- 인덱싱: 전체 폴더 1회성, 부분 갱신 불가

---

### 5.2 TO-BE Architecture

```
┌──────────────────────────────────────────────────────┐
│                    SwiftUI App                        │
│                                                       │
│  SBrainApp.swift                                     │
│    ├── BackendManager  ──start()──→ Django Process    │
│    │     └── .onChange(of: isRunning) ──→ 인증 체크    │
│    ├── NoteStore                                     │
│    │     ├── restoreProjects() ← isRunning 이후 실행  │
│    │     └── handleFileChange() ← FileMonitor 이벤트  │
│    ├── SlackStore                                    │
│    │     ├── @AppStorage("slack.authenticated")      │
│    │     └── checkAuth() ← isRunning 이후 실행        │
│    └── CalendarStore                                 │
│          ├── @AppStorage("calendar.authenticated")   │
│          └── checkAuth() ← isRunning 이후 실행        │
│                                                       │
│  ┌─ NEW ─────────────────────────────────────────┐   │
│  │ FileMonitor (FSEvents)                         │   │
│  │   ├── 프로젝트별 FSEventStream 등록            │   │
│  │   ├── Debounce (1초)                           │   │
│  │   └── → NoteStore.handleFileChange(event)      │   │
│  └────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
                         │ HTTP
┌──────────────────────────────────────────────────────┐
│                    Django Backend                      │
│                                                       │
│  ┌─ NEW ─────────────────────────────────────────┐   │
│  │ Slack State 영속화                              │   │
│  │   .slack_user.json   ← user_id 파일 저장       │   │
│  │   slack_state.db     ← messages, processed_ids │   │
│  │   ready()에서 자동 로드                         │   │
│  └────────────────────────────────────────────────┘   │
│                                                       │
│  Google State:                                        │
│    .google_tokens.json  ← 기존 유지                   │
│    + refresh 실패 시 re_auth_required 응답 추가       │
│                                                       │
│  ┌─ NEW ─────────────────────────────────────────┐   │
│  │ 부분 재인덱싱                                   │   │
│  │   PATCH /api/ingest/  ← 특정 파일 경로만 처리  │   │
│  │   변경/삭제된 파일의 Note + Chunk 갱신          │   │
│  └────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

---

### 5.3 앱 초기화 시퀀스 (TO-BE)

```
SBrainApp.onAppear
  │
  ├── backendManager.start()
  │     ├── kill stale process
  │     ├── check Docker / start local Python
  │     └── health check → isRunning = true ✓
  │
  └── .onChange(of: backendManager.isRunning)  ← NEW
        │
        ├── Phase 1: 프로젝트 복원
        │     └── noteStore.restoreProjects()
        │
        ├── Phase 2: 인증 상태 복원
        │     ├── calendarStore.checkAuth()
        │     │     └── GET /api/calendar/status/
        │     │           ├── authenticated: true → UI 반영
        │     │           └── re_auth_required: true → 재인증 배너
        │     └── slackStore.checkAuth()
        │           └── GET /api/slack/user/
        │                 ├── authenticated: true → UI 반영
        │                 └── false → 재인증 배너
        │
        └── Phase 3: 파일 모니터 시작
              └── fileMonitor.startWatching(projects)
                    └── FSEventStream 등록
```

---

### 5.4 파일 변경 감지 흐름 (TO-BE)

```
외부 편집기에서 파일 수정
  │
  ▼
FSEventStream 이벤트 발생
  │
  ▼
FileMonitor.handleEvent(paths: [String])
  │
  ├── Debounce (1초) ← 연속 변경 병합
  │
  ▼
NoteStore.handleFileChange(changedPaths)
  │
  ├── 1. 변경된 파일의 FolderNode 갱신
  │     └── FolderScanner.scan(at: parentDir)
  │
  ├── 2. @Published projects 업데이트 → UI 자동 갱신
  │
  ├── 3. 변경 파일 재인덱싱 요청
  │     └── PATCH /api/ingest/ { paths: [...] }
  │           ├── 변경된 파일: Note + Chunk 재생성
  │           ├── 삭제된 파일: Note + Chunk + vec_chunks 삭제
  │           └── 추가된 파일: 새 Note + Chunk + 임베딩 생성
  │
  └── 4. Brain Graph 리빌드
        └── noteStore.rebuildGraph()
```

---

### 5.5 Slack 상태 영속화 구조 (TO-BE)

```
Backend 시작
  │
  ├── IntegrationsConfig.ready()
  │     ├── .slack_user.json 로드 → set_current_user(user_id)
  │     ├── slack_state.db 로드 → _messages, _processed_ids 복원
  │     └── Socket Mode 스레드 시작 (기존 user_id로 필터링 즉시 가능)
  │
  ▼
운영 중 상태 변경 시
  │
  ├── user_id 변경 → .slack_user.json 저장
  ├── 새 메시지 수신 → slack_state.db INSERT
  └── 메시지 처리 완료 → slack_state.db UPDATE (processed = true)

Backend 종료 → 재시작
  │
  └── 위 로드 과정 반복 → 이전 상태 완전 복원
```

---

## 6. Decision Points

### DP-1: 파일 모니터링 구현 방식

| 선택지 | 장점 | 단점 |
|--------|------|------|
| **A. FSEventStream (C API)** | 디렉토리 단위 배치 감지, 안정적 | C API 브릿지 필요, 이벤트 지연 ~1초 |
| B. DispatchSource.makeFileSystemObjectSource | Swift 네이티브 | 파일 단위 감시, 대량 파일 시 fd 고갈 |
| C. 주기적 폴링 (Timer) | 구현 간단 | CPU 낭비, 실시간성 부족 |

**추천안: A (FSEventStream)**
- 프로젝트 폴더 단위로 재귀 감시 가능
- macOS 기본 API로 안정성 높음
- 1초 내외 이벤트 수신, debounce와 결합하면 충분

### DP-2: Slack 상태 저장소

| 선택지 | 장점 | 단점 |
|--------|------|------|
| **A. SQLite 파일 (slack_state.db)** | Django ORM 활용, 트랜잭션 안전 | 스키마 관리 필요 |
| B. JSON 파일 | 구현 간단 | 대량 메시지 시 성능 저하, 원자성 없음 |
| C. 기존 brain.db에 테이블 추가 | DB 단일화 | 관심사 분리 위반 |

**추천안: A (SQLite 파일)**
- 메시지 양이 많아질 수 있으므로 DB가 적합
- Django ORM으로 마이그레이션 관리 가능
- brain.db와 분리하여 관심사 유지

### DP-3: SwiftUI 인증 상태 캐시 방식

| 선택지 | 장점 | 단점 |
|--------|------|------|
| **A. @AppStorage (UserDefaults)** | 구현 간단, SwiftUI 네이티브 | 보안 민감 정보에는 부적합 |
| B. Keychain | 보안 강함 | 구현 복잡도 증가 |
| C. 캐시 없음 (현재) | 변경 없음 | 문제 미해결 |

**추천안: A (@AppStorage)**
- 인증 "여부"(bool)만 캐시하므로 보안 위험 낮음
- 토큰 자체는 백엔드에서 관리 (앱에 노출 안 됨)
- 앱 시작 시 UI 즉시 반영, 백엔드 확인 후 갱신

---

## 7. Open Issues

| # | 항목 | 상태 |
|---|------|------|
| 1 | FSEventStream의 latency 설정값 (0.5초 vs 1초) | 테스트 후 결정 |
| 2 | Slack 메시지 영속화 시 최대 보관 건수 (1000건? 무제한?) | 정책 결정 필요 |
| 3 | DB 연결 URL의 Keychain 이동 시점 | v0.8.0에서 함께 할지 별도 이터레이션으로 할지 |
| 4 | 대규모 프로젝트(10,000+ 파일) 시 FSEvents 성능 | 프로파일링 필요 |
| 5 | 백엔드 auto-restart (health check 실패 시) 구현 여부 | 우선순위 판단 필요 |
