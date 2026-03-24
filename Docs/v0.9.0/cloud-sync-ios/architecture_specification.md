# Specification: SBrain v0.9.0 Cloud Sync & iOS Expansion

Type: T4 – Specification
Owner: gicheol
Status: Draft
Last Updated: 2026-03-24

---

## 1. Purpose

v0.9.0 클라우드 동기화 및 iOS 확장에 필요한 **API, 데이터 구조, 신규 컴포넌트 명세**를 정의한다.

---

## 2. 변경 대상 목록

| # | 레이어 | 변경 대상 | 변경 유형 |
|---|--------|----------|----------|
| 1 | Backend | PostgreSQL 전환 | 수정 |
| 2 | Backend | JWT 인증 | 신규 |
| 3 | Backend | Sync Push API | 신규 |
| 4 | macOS | SyncManager | 신규 |
| 5 | macOS | NoteStore sync 연동 | 수정 |
| 6 | iOS | 앱 전체 | 신규 |
| 7 | iOS | 3D BrainMapView (터치) | 신규 |
| 8 | 공통 | TelemetryDeck 통합 | 신규 |

---

## 3. Backend 명세

### 3.1 PostgreSQL 전환

#### settings.py 변경

```python
# AS-IS
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": os.getenv("DB_PATH", BASE_DIR / "brain.db"),
    }
}

# TO-BE (Railway 환경에서만 PostgreSQL, 로컬은 SQLite 유지)
import dj_database_url

if os.getenv("DATABASE_URL"):
    DATABASES = {
        "default": dj_database_url.config(default=os.getenv("DATABASE_URL"))
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": os.getenv("DB_PATH", BASE_DIR / "brain.db"),
        }
    }
```

#### 의존성 추가

```
# requirements.txt
dj-database-url>=2.1,<3.0
psycopg2-binary>=2.9,<3.0   # 이미 존재
```

#### 마이그레이션

```bash
# Railway 환경에서
python manage.py migrate
```

기존 Django 모델(Note, Chunk)은 ORM 기반이므로 PostgreSQL에서 자동 동작.
단, `vec_chunks` (sqlite-vec 가상 테이블)은 Railway에서 사용 불가 → 검색은 TF-IDF만 제공.

---

### 3.2 JWT 인증

#### 의존성

```
# requirements.txt
djangorestframework-simplejwt>=5.3,<6.0
```

#### settings.py 추가

```python
INSTALLED_APPS += ["rest_framework_simplejwt"]

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticatedOrReadOnly",
    ],
    "UNAUTHENTICATED_USER": None,
}

# 로컬 Django는 인증 없이 동작 (기존 호환)
if not os.getenv("DATABASE_URL"):
    REST_FRAMEWORK["DEFAULT_AUTHENTICATION_CLASSES"] = []
    REST_FRAMEWORK["DEFAULT_PERMISSION_CLASSES"] = [
        "rest_framework.permissions.AllowAny",
    ]

from datetime import timedelta
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(hours=24),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=30),
}
```

#### 인증 API 엔드포인트

```
POST /api/auth/token/          → JWT access + refresh 토큰 발급
POST /api/auth/token/refresh/  → access 토큰 갱신
```

#### URL 라우팅

```python
# config/urls.py
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

urlpatterns += [
    path("api/auth/token/", TokenObtainPairView.as_view(), name="token-obtain"),
    path("api/auth/token/refresh/", TokenRefreshView.as_view(), name="token-refresh"),
]
```

#### 초기 유저 생성

```bash
# Railway에서 1회 실행
python manage.py createsuperuser --username gicheol --email gc.yang@example.com
```

---

### 3.3 Sync Push API

#### 엔드포인트

```
POST /api/sync/push/
Authorization: Bearer {jwt_token}
```

#### Request

```json
{
  "notes": [
    {
      "id": "sha256_of_relative_path",
      "path": "my-project/subfolder/note.md",
      "filename": "note.md",
      "content": "# Note Title\n\nFull markdown content...",
      "updated_at": "2026-03-24T10:30:00+09:00"
    }
  ],
  "deleted_ids": ["sha256hash1"]
}
```

#### 필드 정의

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `notes` | array | N | 추가/수정된 노트 목록 |
| `notes[].id` | string | Y | SHA256(상대경로) — Note PK |
| `notes[].path` | string | Y | 프로젝트 상대 경로 |
| `notes[].filename` | string | Y | 파일명 |
| `notes[].content` | string | Y | 파일 전체 내용 |
| `notes[].updated_at` | string | Y | ISO 8601 수정 시각 |
| `deleted_ids` | string[] | N | 삭제된 노트 ID 목록 |

#### Response (200 OK)

```json
{
  "synced": 3,
  "deleted": 1,
  "errors": []
}
```

#### 처리 로직

```python
# notes/views.py

@api_view(["POST"])
@permission_classes([IsAuthenticated])
def sync_push(request):
    notes_data = request.data.get("notes", [])
    deleted_ids = request.data.get("deleted_ids", [])
    synced, errors = 0, []

    # 1. 삭제
    deleted = Note.objects.filter(id__in=deleted_ids).count()
    Chunk.objects.filter(note_id__in=deleted_ids).delete()
    Note.objects.filter(id__in=deleted_ids).delete()

    # 2. Upsert
    for note_data in notes_data:
        try:
            Note.objects.update_or_create(
                id=note_data["id"],
                defaults={
                    "path": note_data["path"],
                    "filename": note_data["filename"],
                    "content": note_data["content"],
                }
            )
            # Chunk 재생성
            _rebuild_chunks(note_data["id"], note_data["content"])
            synced += 1
        except Exception as e:
            errors.append({"id": note_data["id"], "error": str(e)})

    return Response({"synced": synced, "deleted": deleted, "errors": errors})
```

---

## 4. macOS 명세

### 4.1 SyncManager (신규)

#### 파일: `Services/SyncManager.swift`

```swift
@MainActor
class SyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncAt: Date?
    @Published var syncError: String?

    private let api = APIClient.shared

    /// 변경된 노트를 Railway에 push
    func pushChanges(notes: [SyncNote], deletedIds: [String]) async {
        guard !notes.isEmpty || !deletedIds.isEmpty else { return }
        isSyncing = true
        do {
            try await api.syncPush(notes: notes, deletedIds: deletedIds)
            lastSyncAt = Date()
            syncError = nil
        } catch {
            syncError = "동기화 실패: \(error.localizedDescription)"
        }
        isSyncing = false
    }

    /// 앱 시작 시 전체 동기화 (로컬 → Railway)
    func fullSync(projects: [ProjectFolder]) async { ... }
}
```

#### SyncNote 모델

```swift
struct SyncNote: Codable {
    let id: String          // SHA256(상대경로)
    let path: String        // 프로젝트 상대 경로
    let filename: String
    let content: String
    let updatedAt: String   // ISO 8601
}
```

#### 경로 변환 로직

```swift
/// 절대 경로 → 프로젝트 상대 경로
/// "/Users/gc.yang/projects/notes/sub/file.md"
///  → "notes/sub/file.md" (프로젝트명/하위경로)
func relativePath(absolutePath: String, projectPath: String) -> String {
    let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
    let relative = absolutePath.replacingOccurrences(of: projectPath + "/", with: "")
    return "\(projectName)/\(relative)"
}
```

### 4.2 NoteStore sync 연동

#### 변경: `handleFileChange()` 에 sync push 추가

```swift
// 기존 코드 유지 + sync push 추가
func handleFileChange(changedPaths: [String]) {
    // ... 기존 로컬 처리 (리스캔, partial_ingest) ...

    // 신규: Railway 동기화
    let syncNotes = existing.compactMap { path -> SyncNote? in
        guard let content = FolderScanner.readContent(at: path),
              let project = projects.first(where: { path.hasPrefix($0.path) })
        else { return nil }
        return SyncNote(
            id: sha256(relativePath(absolutePath: path, projectPath: project.path)),
            path: relativePath(absolutePath: path, projectPath: project.path),
            filename: URL(fileURLWithPath: path).lastPathComponent,
            content: content,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
    let deletedIds = deleted.compactMap { path -> String? in
        guard let project = projects.first(where: { path.hasPrefix($0.path) })
        else { return nil }
        return sha256(relativePath(absolutePath: path, projectPath: project.path))
    }

    Task { await syncManager.pushChanges(notes: syncNotes, deletedIds: deletedIds) }
}
```

### 4.3 APIClient sync 메서드

```swift
/// Railway에 변경분 동기화
func syncPush(notes: [SyncNote], deletedIds: [String]) async throws {
    let url = URL(string: "\(cloudBaseURL)/api/sync/push/")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")

    let body: [String: Any] = [
        "notes": notes.map { ... },
        "deleted_ids": deletedIds,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw APIError.syncFailed
    }
}
```

---

## 5. iOS 명세

### 5.1 프로젝트 구성

#### project.yml 멀티타겟

```yaml
targets:
  SBrain:
    type: application
    platform: macOS
    sources:
      - path: SBrain/Shared
      - path: SBrain/macOS
    dependencies:
      - package: SwiftTerm
      - package: Sparkle
    settings:
      base:
        MARKETING_VERSION: "0.9.0"
        CURRENT_PROJECT_VERSION: 8

  SBrain-iOS:
    type: application
    platform: iOS
    sources:
      - path: SBrain/Shared
      - path: SBrain/iOS
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.hanmari.sbrain.ios
        MARKETING_VERSION: "0.9.0"
        CURRENT_PROJECT_VERSION: 1
        TARGETED_DEVICE_FAMILY: "1,2"
        IPHONEOS_DEPLOYMENT_TARGET: "17.0"
```

### 5.2 디렉토리 구조

```
SBrain/
├── Shared/                    ← macOS + iOS 공유 (19개)
│   ├── Models/
│   │   ├── Note.swift
│   │   ├── SlackModels.swift
│   │   └── CalendarModels.swift
│   ├── Services/
│   │   ├── APIClient.swift
│   │   ├── LocalGraphBuilder.swift
│   │   └── SyncManager.swift   (신규)
│   ├── Views/
│   │   ├── CalendarView.swift
│   │   ├── SlackAgentView.swift
│   │   ├── NoteListView.swift
│   │   ├── DatabaseBrowserView.swift
│   │   └── SettingsView.swift
│   └── Theme/
│       ├── DesignTokens.swift  (#if os 분기)
│       ├── SBButton.swift
│       └── SBCard.swift
├── macOS/                     ← macOS 전용 (14개)
│   ├── SBrainApp+macOS.swift
│   ├── ContentView+macOS.swift
│   ├── BackendManager.swift
│   ├── FileMonitor.swift
│   ├── NoteStore+macOS.swift  (NSOpenPanel, 로컬 Django 연동)
│   ├── NoteDetailView+macOS.swift (NSViewRepresentable)
│   ├── BrainMapView+macOS.swift   (NSEvent, 스크롤 휠)
│   ├── TerminalView.swift
│   ├── TerminalManager.swift
│   └── HandTrackingManager.swift
└── iOS/                       ← iOS 전용 (신규)
    ├── SBrainApp+iOS.swift
    ├── ContentView+iOS.swift  (TabView 기반)
    ├── NoteStore+iOS.swift    (Railway API 전용, 캐시)
    ├── NoteDetailView+iOS.swift (UIViewRepresentable)
    ├── BrainMapView+iOS.swift   (터치 제스처)
    ├── AuthView.swift           (로그인 화면)
    └── CacheManager.swift       (오프라인 캐시)
```

### 5.3 iOS BrainMapView 터치 제스처

| 제스처 | macOS (기존) | iOS |
|--------|-------------|-----|
| 회전 | 마우스 드래그 | 1-finger 드래그 |
| 줌 | 스크롤 휠 / MagnifyGesture | 핀치 제스처 |
| 뉴런 선택 | 클릭 | 탭 |
| 포커스 | 더블클릭 | 더블탭 |
| 패닝 | Option+드래그 | 2-finger 드래그 |

### 5.4 iOS CacheManager

```swift
class CacheManager {
    private let cacheDir: URL  // ~/Library/Caches/SBrain/

    /// 노트 내용 캐시 (JSON 파일)
    func cacheNote(_ note: Memory) { ... }

    /// 캐시된 노트 로드 (오프라인용)
    func loadCachedNote(id: String) -> Memory? { ... }

    /// 캐시된 노트 목록
    func loadCachedNotes() -> [Memory] { ... }

    /// 캐시 크기 확인 + 오래된 항목 정리
    func cleanup(maxAge: TimeInterval = 7 * 24 * 3600) { ... }
}
```

### 5.5 iOS 앱 흐름

```
앱 실행
  │
  ├── 저장된 JWT 확인
  │     ├── 있음 → 토큰 유효성 확인 → 메인 화면
  │     └── 없음 → AuthView (로그인)
  │
  └── 메인 TabView
        ├── Brain Map 탭
        │     └── GET /api/graph/ → 3D 렌더링
        ├── Notes 탭
        │     └── GET /api/notes/ → 목록 → 탭 → GET /api/notes/{id}/ → 상세
        ├── Search 탭
        │     └── POST /api/search/ → 결과 목록
        └── Settings 탭
              └── 연결 상태, 캐시 관리, 로그아웃
```

---

## 6. TelemetryDeck 명세

### 통합 방식

```swift
// Package 추가
// .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0")

// 초기화 (SBrainApp)
import TelemetryDeck

TelemetryDeck.initialize(config: .init(appID: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"))
```

### 이벤트 목록

| 이벤트 이름 | 트리거 | 파라미터 |
|------------|--------|---------|
| `app.launch` | 앱 시작 | `platform: macOS/iOS` |
| `view.brainmap` | Brain Map 진입 | `neuronCount` |
| `view.brainmap.duration` | Brain Map 이탈 | `seconds` |
| `view.list` | 리스트 뷰 진입 | — |
| `view.slack` | Slack 뷰 진입 | — |
| `view.calendar` | Calendar 뷰 진입 | — |
| `search.recall` | 검색 실행 | `resultCount` |
| `sync.push` | 동기화 push | `noteCount` |
| `sync.error` | 동기화 실패 | `error` |
| `auth.login` | 로그인 | `platform` |
| `nps.score` | NPS 제출 | `score: 0~10` |

---

## 7. 제약 사항

| # | 항목 | 제약 |
|---|------|------|
| 1 | Railway PostgreSQL | 무료 티어 500MB — 노트 수만 건 수준 충분 |
| 2 | sync push 요청 크기 | 1회 요청 최대 10MB (Railway 기본) — 대용량 파일은 분할 |
| 3 | iOS 최소 버전 | iOS 17.0 (Canvas + TimelineView 요구) |
| 4 | vec_chunks | PostgreSQL에서 sqlite-vec 사용 불가 → Railway 검색은 TF-IDF만 |
| 5 | 오프라인 iOS | 캐시된 노트만 열람. 검색/그래프 불가 |
| 6 | 동시 편집 | 미지원 — macOS에서만 편집, 충돌 없음 |

---

## 8. 구현 우선순위

| 순서 | 항목 | 의존성 |
|------|------|--------|
| 1 | PostgreSQL 전환 (settings.py + dj-database-url) | 없음 |
| 2 | JWT 인증 (simplejwt + URL 라우팅) | #1 |
| 3 | Sync Push API (views.py + urls.py) | #2 |
| 4 | Railway 재배포 + PostgreSQL 추가 | #1~3 |
| 5 | macOS SyncManager + NoteStore 연동 | #4 |
| 6 | 테스트 (pytest + CI) | #3 |
| 7 | 디렉토리 재구성 (Shared/macOS/iOS) | 없음 (병렬 가능) |
| 8 | iOS 앱 기본 구조 (TabView, AuthView) | #7 |
| 9 | iOS BrainMapView (터치 제스처) | #8 |
| 10 | iOS NoteDetailView | #8 |
| 11 | TelemetryDeck 통합 | #8 |
| 12 | TestFlight 배포 | #8~10 |

---

## 9. 변경 파일 요약

### Backend (Python)

| 파일 | 변경 유형 |
|------|----------|
| `config/settings.py` | 수정 — PostgreSQL 조건부 전환, JWT 설정 |
| `config/urls.py` | 수정 — JWT URL, sync push URL 추가 |
| `notes/views.py` | 수정 — `sync_push()` 뷰 추가 |
| `notes/urls.py` | 수정 — sync/push/ 경로 추가 |
| `requirements.txt` | 수정 — dj-database-url, simplejwt 추가 |

### macOS (Swift)

| 파일 | 변경 유형 |
|------|----------|
| `Services/SyncManager.swift` | **신규** |
| `Services/APIClient.swift` | 수정 — syncPush(), cloudBaseURL 추가 |
| `Services/NoteStore.swift` | 수정 — handleFileChange에 sync 추가 |
| `SBrainApp.swift` | 수정 — SyncManager StateObject 추가 |
| `app/project.yml` | 수정 — 멀티타겟 구성 |

### iOS (Swift, 전부 신규)

| 파일 | 설명 |
|------|------|
| `iOS/SBrainApp+iOS.swift` | iOS 앱 엔트리포인트 |
| `iOS/ContentView+iOS.swift` | TabView 기반 메인 레이아웃 |
| `iOS/AuthView.swift` | 로그인/API Key 입력 |
| `iOS/NoteStore+iOS.swift` | Railway API 전용 NoteStore |
| `iOS/BrainMapView+iOS.swift` | 터치 제스처 3D Brain Map |
| `iOS/NoteDetailView+iOS.swift` | WKWebView 마크다운 렌더링 |
| `iOS/CacheManager.swift` | 오프라인 캐시 |
