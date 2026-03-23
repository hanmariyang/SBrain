# Specification: SBrain v0.8.0 Architecture Improvement

Type: T4 – Specification
Owner: gicheol
Status: Draft
Last Updated: 2026-03-24

---

## 1. Purpose

v0.8.0 아키텍처 개선에 필요한 **API 변경, 데이터 구조, 신규 컴포넌트 명세**를 정의한다.
개발 시 이 문서를 구현 기준으로 사용한다.

---

## 2. 변경 대상 목록

| # | 레이어 | 변경 대상 | 변경 유형 |
|---|--------|----------|----------|
| 1 | Backend | Slack 인증 상태 영속화 | 신규 |
| 2 | Backend | Slack 메시지 상태 영속화 | 신규 |
| 3 | Backend | Google Calendar 토큰 복원 안정화 | 수정 |
| 4 | Backend | 부분 재인덱싱 API | 신규 |
| 5 | SwiftUI | FileMonitor (FSEvents) | 신규 |
| 6 | SwiftUI | 앱 초기화 시퀀스 개선 | 수정 |
| 7 | SwiftUI | 인증 상태 로컬 캐시 | 신규 |

---

## 3. Backend 명세

### 3.1 Slack 인증 상태 영속화

#### 저장 파일
- **경로**: `backend/.slack_user.json`
- **생성 시점**: Slack OAuth 콜백 성공 시
- **로드 시점**: `IntegrationsConfig.ready()`

#### 데이터 구조

```json
{
  "user_id": "U1234567890",
  "user_name": "gicheol",
  "authenticated_at": "2026-03-24T10:30:00+09:00"
}
```

#### 변경 파일 및 로직

**`integrations/slack_service.py`**

```python
# 신규 함수
SLACK_USER_FILE = Path(__file__).resolve().parent.parent / ".slack_user.json"

def save_user(user_id: str, user_name: str = ""):
    """user_id를 파일에 영구 저장"""
    data = {
        "user_id": user_id,
        "user_name": user_name,
        "authenticated_at": datetime.now().isoformat(),
    }
    SLACK_USER_FILE.write_text(json.dumps(data, ensure_ascii=False))

def load_user() -> dict | None:
    """저장된 user_id 로드. 없으면 None"""
    if not SLACK_USER_FILE.exists():
        return None
    try:
        return json.loads(SLACK_USER_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return None
```

**`integrations/oauth_callback.py`** — `slack_oauth_callback()` 수정

```python
# 기존: slack_service.set_current_user(user_id)
# 변경: 파일 저장 추가
slack_service.set_current_user(user_id)
slack_service.save_user(user_id, user_name=user_name)
```

**`integrations/apps.py`** — `IntegrationsConfig.ready()` 수정

```python
def ready(self):
    from .slack_service import load_user, set_current_user, start_socket_mode

    # 저장된 user_id 복원
    saved = load_user()
    if saved:
        set_current_user(saved["user_id"])

    # Socket Mode 시작 (기존 로직 유지)
    start_socket_mode()
```

---

### 3.2 Slack 메시지 상태 영속화

#### 데이터베이스
- **파일**: `backend/slack_state.db` (별도 SQLite)
- **테이블**: `slack_messages`

#### 스키마 정의

```sql
CREATE TABLE IF NOT EXISTS slack_messages (
    id          TEXT PRIMARY KEY,      -- Slack message ts
    channel     TEXT NOT NULL,
    user_id     TEXT,
    user_name   TEXT,
    text        TEXT NOT NULL,
    thread_ts   TEXT,
    received_at TEXT NOT NULL,          -- ISO 8601
    processed   INTEGER DEFAULT 0,     -- 0: pending, 1: processed
    urgency     TEXT,                   -- AI 분석 결과
    action_type TEXT,
    summary     TEXT,
    draft_reply TEXT
);

CREATE INDEX IF NOT EXISTS idx_slack_messages_processed
    ON slack_messages(processed);

CREATE INDEX IF NOT EXISTS idx_slack_messages_channel
    ON slack_messages(channel);
```

#### 변경 로직

**`integrations/slack_service.py`**

```python
import sqlite3
from pathlib import Path

SLACK_DB_PATH = Path(__file__).resolve().parent.parent / "slack_state.db"

def _get_slack_db():
    """slack_state.db 연결. 테이블 없으면 생성."""
    conn = sqlite3.connect(str(SLACK_DB_PATH))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS slack_messages (
            id TEXT PRIMARY KEY,
            channel TEXT NOT NULL,
            user_id TEXT,
            user_name TEXT,
            text TEXT NOT NULL,
            thread_ts TEXT,
            received_at TEXT NOT NULL,
            processed INTEGER DEFAULT 0,
            urgency TEXT,
            action_type TEXT,
            summary TEXT,
            draft_reply TEXT
        )
    """)
    conn.commit()
    return conn

def persist_message(msg: dict):
    """메시지를 DB에 저장 (중복 시 무시)"""
    conn = _get_slack_db()
    try:
        conn.execute(
            "INSERT OR IGNORE INTO slack_messages "
            "(id, channel, user_id, user_name, text, thread_ts, received_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (msg["ts"], msg["channel"], msg.get("user"),
             msg.get("user_name"), msg["text"],
             msg.get("thread_ts"), datetime.now().isoformat())
        )
        conn.commit()
    finally:
        conn.close()

def load_pending_messages() -> list[dict]:
    """미처리 메시지 로드"""
    conn = _get_slack_db()
    try:
        rows = conn.execute(
            "SELECT * FROM slack_messages WHERE processed = 0 "
            "ORDER BY received_at DESC"
        ).fetchall()
        return [_row_to_dict(r) for r in rows]
    finally:
        conn.close()

def mark_processed(message_id: str):
    """메시지를 처리 완료로 표시"""
    conn = _get_slack_db()
    try:
        conn.execute(
            "UPDATE slack_messages SET processed = 1 WHERE id = ?",
            (message_id,)
        )
        conn.commit()
    finally:
        conn.close()
```

---

### 3.3 Google Calendar 토큰 복원 안정화

#### 변경 파일: `integrations/calendar_service.py`

**`_get_service()` 메서드 수정**

```python
def _get_service(self):
    """토큰 로드 → 리프레시 → 실패 시 명확한 상태 반환"""
    creds = self._load_tokens()
    if not creds:
        raise AuthRequiredError("no_tokens")

    if creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            self._save_tokens(creds)
        except google.auth.exceptions.RefreshError:
            # refresh_token 만료/취소
            self._delete_tokens()
            raise AuthRequiredError("refresh_failed")

    return build("calendar", "v3", credentials=creds)
```

**`/api/calendar/status/` 응답 변경**

```json
// 기존
{ "authenticated": true }

// 변경: re_auth_required 필드 추가
{ "authenticated": true, "re_auth_required": false }
{ "authenticated": false, "re_auth_required": true, "reason": "refresh_failed" }
{ "authenticated": false, "re_auth_required": false }
```

#### 응답 필드 정의

| 필드 | 타입 | 설명 |
|------|------|------|
| `authenticated` | boolean | 현재 유효한 인증 상태 |
| `re_auth_required` | boolean | 재인증 필요 여부 (refresh 실패 등) |
| `reason` | string? | 재인증 필요 사유 (`"refresh_failed"`, `"no_tokens"`) |

---

### 3.4 부분 재인덱싱 API

#### 엔드포인트

```
PATCH /api/ingest/
```

#### Request

```json
{
  "paths": [
    "/Users/user/projects/notes/new_file.md",
    "/Users/user/projects/notes/modified_file.md"
  ],
  "deleted_paths": [
    "/Users/user/projects/notes/removed_file.md"
  ]
}
```

#### 필드 정의

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `paths` | string[] | N | 추가/수정된 파일 경로 목록 |
| `deleted_paths` | string[] | N | 삭제된 파일 경로 목록 |

#### Response (200 OK)

```json
{
  "updated": 2,
  "deleted": 1,
  "errors": []
}
```

#### 처리 로직

```python
# notes/views.py

@api_view(["PATCH"])
def partial_ingest(request):
    paths = request.data.get("paths", [])
    deleted_paths = request.data.get("deleted_paths", [])
    updated, errors = 0, []

    # 1. 삭제된 파일 처리
    deleted = 0
    for path in deleted_paths:
        note_id = hashlib.sha256(path.encode()).hexdigest()[:64]
        Chunk.objects.filter(note_id=note_id).delete()
        # vec_chunks에서도 삭제 (raw SQL)
        _delete_vec_chunks(note_id)
        Note.objects.filter(id=note_id).delete()
        deleted += 1

    # 2. 추가/수정된 파일 처리
    for path in paths:
        try:
            content = Path(path).read_text(encoding="utf-8")
            note_id = hashlib.sha256(path.encode()).hexdigest()[:64]

            # Note upsert
            Note.objects.update_or_create(
                id=note_id,
                defaults={
                    "path": path,
                    "filename": Path(path).name,
                    "content": content,
                }
            )

            # 기존 Chunk 삭제 후 재생성
            Chunk.objects.filter(note_id=note_id).delete()
            _delete_vec_chunks(note_id)
            chunks = _split_chunks(content)
            _create_chunks(note_id, chunks)

            updated += 1
        except Exception as e:
            errors.append({"path": path, "error": str(e)})

    return Response({
        "updated": updated,
        "deleted": deleted,
        "errors": errors,
    })
```

#### URL 라우팅 변경

```python
# notes/urls.py — 기존 ingest URL에 PATCH 메서드 추가
urlpatterns = [
    path("ingest/", views.ingest),          # POST: 전체 인덱싱 (기존)
    path("ingest/partial/", views.partial_ingest),  # PATCH: 부분 인덱싱 (신규)
    # ... 기존 유지
]
```

---

## 4. SwiftUI 명세

### 4.1 FileMonitor (FSEvents 기반)

#### 신규 파일: `Services/FileMonitor.swift`

```swift
import Foundation

@MainActor
class FileMonitor: ObservableObject {

    private var streams: [String: FSEventStreamRef] = [:]
    private var debounceTask: Task<Void, Never>?
    private var pendingChanges: Set<String> = []

    var onFilesChanged: (([String]) -> Void)?

    /// 프로젝트 경로에 대한 FSEvents 감시 시작
    func startWatching(path: String) {
        guard streams[path] == nil else { return }

        let pathCF = path as CFString
        var context = FSEventStreamContext(...)

        let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [pathCF] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,    // latency: 1초
            UInt32(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer
            )
        )

        FSEventStreamScheduleWithRunLoop(
            stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )
        FSEventStreamStart(stream)
        streams[path] = stream
    }

    /// 감시 중지
    func stopWatching(path: String) {
        guard let stream = streams.removeValue(forKey: path) else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// 모든 감시 중지
    func stopAll() {
        for path in streams.keys {
            stopWatching(path: path)
        }
    }

    /// FSEvents 콜백에서 호출 — 변경 경로 수집 + debounce
    func handleRawEvent(paths: [String]) {
        for path in paths {
            pendingChanges.insert(path)
        }

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1초
            guard !Task.isCancelled else { return }

            let changes = Array(pendingChanges)
            pendingChanges.removeAll()
            onFilesChanged?(changes)
        }
    }
}
```

#### 인터페이스 정의

| 메서드 | 파라미터 | 설명 |
|--------|---------|------|
| `startWatching(path:)` | String | 프로젝트 폴더 FSEvents 감시 시작 |
| `stopWatching(path:)` | String | 특정 폴더 감시 중지 |
| `stopAll()` | — | 모든 감시 중지 |
| `onFilesChanged` | `[String] -> Void` | 변경된 파일 경로 콜백 |

#### FSEventStream 설정값

| 파라미터 | 값 | 설명 |
|---------|-----|------|
| `latency` | 1.0초 | 이벤트 배치 간격 |
| `flags` | `kFSEventStreamCreateFlagFileEvents` | 파일 단위 이벤트 수신 |
| `sinceWhen` | `kFSEventStreamEventIdSinceNow` | 현재 시점 이후 이벤트만 |

---

### 4.2 앱 초기화 시퀀스 변경

#### 변경 파일: `Views/ContentView.swift`

**AS-IS**
```swift
.task {
    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2초 하드코딩
    noteStore.restoreProjects()
}
```

**TO-BE**
```swift
.onChange(of: backendManager.isRunning) { _, isRunning in
    guard isRunning else { return }

    Task {
        // Phase 1: 프로젝트 복원
        noteStore.restoreProjects()

        // Phase 2: 인증 상태 복원
        async let calAuth: () = calendarStore.checkAuth()
        async let slkAuth: () = slackStore.checkAuth()
        _ = await (calAuth, slkAuth)

        // Phase 3: 파일 모니터 시작
        for project in noteStore.projects {
            fileMonitor.startWatching(path: project.path)
        }
    }
}
```

#### 변경 파일: `SBrainApp.swift`

```swift
// 신규 StateObject 추가
@StateObject private var fileMonitor = FileMonitor()

// environmentObject 주입
.environmentObject(fileMonitor)
```

---

### 4.3 NoteStore 파일 변경 핸들러

#### 변경 파일: `Services/NoteStore.swift`

**신규 메서드**

```swift
/// FileMonitor 이벤트 수신 → 부분 리스캔 + 재인덱싱
func handleFileChange(changedPaths: [String]) {
    let supportedExtensions: Set<String> = ["md", "html", "htm"]

    // 1. 변경된 프로젝트 식별
    let affectedProjects = projects.filter { project in
        changedPaths.contains { $0.hasPrefix(project.path) }
    }

    // 2. 프로젝트별 부분 리스캔
    for (index, project) in projects.enumerated() {
        guard affectedProjects.contains(where: { $0.path == project.path }) else { continue }
        guard let newRoot = FolderScanner.scan(at: project.path) else { continue }

        projects[index] = ProjectFolder(
            path: project.path,
            name: project.name,
            rootFolder: newRoot,
            isBaseFolder: project.isBaseFolder
        )
    }

    // 3. 변경된 파일만 재인덱싱 요청
    let mdPaths = changedPaths.filter {
        supportedExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
    }

    let existing = mdPaths.filter { FileManager.default.fileExists(atPath: $0) }
    let deleted = mdPaths.filter { !FileManager.default.fileExists(atPath: $0) }

    if !existing.isEmpty || !deleted.isEmpty {
        Task {
            try? await api.partialIngest(paths: existing, deletedPaths: deleted)
            rebuildGraph()
        }
    }
}
```

---

### 4.4 인증 상태 로컬 캐시

#### 변경 파일: `Services/SlackStore.swift`

```swift
// 기존
@Published var isConnected = false
@Published var userName: String = ""

// 변경: @AppStorage 캐시 추가
@AppStorage("sbrain.slack.authenticated") private var cachedAuth = false
@AppStorage("sbrain.slack.userName") private var cachedUserName = ""

@Published var isConnected = false {
    didSet { cachedAuth = isConnected }
}
@Published var userName: String = "" {
    didSet { cachedUserName = userName }
}

// init에서 캐시 복원
init() {
    isConnected = cachedAuth
    userName = cachedUserName
}
```

#### 변경 파일: `Services/CalendarStore.swift`

```swift
// 동일 패턴
@AppStorage("sbrain.calendar.authenticated") private var cachedAuth = false

@Published var isAuthenticated = false {
    didSet { cachedAuth = isAuthenticated }
}

init() {
    isAuthenticated = cachedAuth
}
```

---

### 4.5 APIClient 신규 메서드

#### 변경 파일: `Services/APIClient.swift`

```swift
/// 부분 재인덱싱 요청
func partialIngest(paths: [String], deletedPaths: [String]) async throws {
    var request = URLRequest(url: baseURL.appendingPathComponent("ingest/partial/"))
    request.httpMethod = "PATCH"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
        "paths": paths,
        "deleted_paths": deletedPaths,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw APIError.serverError
    }
}
```

---

## 5. 제약 사항

| # | 항목 | 제약 |
|---|------|------|
| 1 | FSEventStream | macOS 10.13+ 필요 (현재 타겟 호환) |
| 2 | slack_state.db | brain.db와 별도 파일 — Django DATABASES에 추가하지 않고 직접 sqlite3 사용 |
| 3 | 부분 재인덱싱 | 임베딩 API 호출 포함 — rate limit 고려 필요 (배치 5개 단위) |
| 4 | @AppStorage | 인증 "여부"(bool)만 캐시. 토큰/시크릿은 저장하지 않음 |
| 5 | FSEvents latency | 최소 1초 — 0.5초 이하 설정 시 CPU 부하 증가 |
| 6 | .slack_user.json | 단일 유저 전용. 멀티 유저는 v0.8.0 범위 밖 |

---

## 6. 구현 우선순위

| 순서 | 항목 | 예상 난이도 | 의존성 |
|------|------|-----------|--------|
| 1 | Slack user_id 영구 저장 (3.1) | 낮음 | 없음 |
| 2 | 앱 초기화 시퀀스 개선 (4.2) | 낮음 | 없음 |
| 3 | 인증 상태 로컬 캐시 (4.4) | 낮음 | 없음 |
| 4 | Google 토큰 복원 안정화 (3.3) | 중간 | 없음 |
| 5 | Slack 메시지 영속화 (3.2) | 중간 | #1 |
| 6 | FileMonitor 구현 (4.1) | 높음 | 없음 |
| 7 | NoteStore 변경 핸들러 (4.3) | 중간 | #6 |
| 8 | 부분 재인덱싱 API (3.4) | 중간 | #7 |

---

## 7. 변경 파일 요약

### Backend (Python)

| 파일 | 변경 유형 |
|------|----------|
| `integrations/slack_service.py` | 수정 — user 영속화 함수 추가, 메시지 DB 함수 추가 |
| `integrations/oauth_callback.py` | 수정 — `save_user()` 호출 추가 |
| `integrations/apps.py` | 수정 — `ready()`에서 저장된 user 로드 |
| `integrations/calendar_service.py` | 수정 — refresh 실패 처리, AuthRequiredError |
| `integrations/calendar_views.py` | 수정 — status 응답에 `re_auth_required` 추가 |
| `notes/views.py` | 수정 — `partial_ingest()` 뷰 추가 |
| `notes/urls.py` | 수정 — `ingest/partial/` 경로 추가 |

### SwiftUI (Swift)

| 파일 | 변경 유형 |
|------|----------|
| `Services/FileMonitor.swift` | **신규** — FSEvents 기반 파일 모니터 |
| `Services/NoteStore.swift` | 수정 — `handleFileChange()` 추가 |
| `Services/APIClient.swift` | 수정 — `partialIngest()` 추가 |
| `Services/SlackStore.swift` | 수정 — @AppStorage 캐시 추가 |
| `Services/CalendarStore.swift` | 수정 — @AppStorage 캐시 추가 |
| `Views/ContentView.swift` | 수정 — 초기화 시퀀스 `.onChange` 기반으로 변경 |
| `SBrainApp.swift` | 수정 — FileMonitor StateObject 추가 |
