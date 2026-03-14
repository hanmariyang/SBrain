# Specification: SBrain REST API & Data Model

Type: T4 – Specification
Owner: gicheol
Status: Done
Last Updated: 2026-03-14

---

## 1. Purpose

SBrain 백엔드 REST API 엔드포인트와 데이터 모델을 명세한다.

---

## 2. Entity / Table List

| Table | Description |
|-------|-------------|
| `notes_note` | 문서 파일 메타데이터 (Django ORM) |
| `notes_chunk` | 문서 청크 텍스트 (Django ORM) |
| `vec_chunks` | 청크 임베딩 벡터 (sqlite-vec virtual table) |

---

## 3. Field Definition

### notes_note

| Field | Type | Source | Nullable | Note |
|-------|------|--------|----------|------|
| id | VARCHAR(64) PK | SHA256(file_path) | N | |
| path | TEXT | 파일 절대 경로 | N | |
| filename | VARCHAR(255) | 파일명 | N | |
| content | TEXT | 파일 전체 내용 | N | |
| updated_at | DATETIME | 파일 mtime | N | |

### notes_chunk

| Field | Type | Source | Nullable | Note |
|-------|------|--------|----------|------|
| id | VARCHAR(128) PK | `{note_id}_{index}` | N | |
| note_id | FK → notes_note | | N | |
| chunk_text | TEXT | 500자 청크 | N | |
| chunk_index | INTEGER | 청크 순번 | N | |

### vec_chunks (sqlite-vec)

| Field | Type | Note |
|-------|------|------|
| id | TEXT | chunk.id와 동일 |
| embedding | FLOAT[1024] | voyage-3 임베딩 벡터 |

---

## 4. API Endpoints

### POST /api/ingest/

폴더를 스캔하여 임베딩 생성 (백그라운드 실행)

**Request**
```json
{ "folder_path": "/Users/user/notes" }
```

**Response** `200`
```json
{ "status": "started", "folder_path": "/Users/user/notes" }
```

### GET /api/notes/

Memory 목록 반환

**Response** `200`
```json
[
  {
    "id": "abc123",
    "filename": "note.md",
    "path": "/Users/user/notes/note.md",
    "updated_at": "2026-03-14T09:00:00Z",
    "preview": "첫 3줄 미리보기"
  }
]
```

### GET /api/notes/{id}/

Memory 상세 (전체 content 포함)

**Response** `200`
```json
{
  "id": "abc123",
  "filename": "note.md",
  "path": "/Users/user/notes/note.md",
  "content": "전체 마크다운 내용...",
  "updated_at": "2026-03-14T09:00:00Z"
}
```

### POST /api/search/

벡터 유사도 기반 Recall (시맨틱 검색)

**Request**
```json
{ "query": "검색 키워드", "limit": 10 }
```

**Response** `200`
```json
[
  {
    "note_id": "abc123",
    "filename": "note.md",
    "path": "/Users/user/notes/note.md",
    "chunk_text": "매칭된 청크 텍스트...",
    "score": 0.87
  }
]
```

### GET /api/status/

Memorize(인덱싱) 진행 상태

**Response** `200`
```json
{
  "running": true,
  "total": 50,
  "done": 23,
  "current_file": "note.md"
}
```

### GET /api/graph/?threshold=0.5

Brain Graph 데이터 (뉴런 + 시냅스)

**Query Params**: `threshold` (코사인 유사도 최소값, default 0.5)

**Response** `200`
```json
{
  "neurons": [
    {
      "id": "abc123",
      "filename": "note.md",
      "preview": "미리보기...",
      "x": 0.45,
      "y": 0.62,
      "chunk_count": 5,
      "project_tag": ""
    }
  ],
  "synapses": [
    {
      "source": "abc123",
      "target": "def456",
      "strength": 0.78
    }
  ]
}
```

---

## 5. Constraints

- `limit` 범위: 1–50 (search)
- `threshold` 범위: 0.0–1.0 (graph)
- 청크 크기: 500자, 오버랩 50자
- 임베딩 배치: 20개씩 (rate limit 대응)
- 임베딩 모델: `voyage-3` (1024 dimensions)
- 포트: `8765` (고정)
- 인증: 없음 (AllowAny, localhost only)

---

## 6. Supported File Types

| Extension | Type | Embedding | Viewer |
|-----------|------|-----------|--------|
| `.md` | Markdown | O | MarkdownWebView |
| `.html` | HTML | O | HTMLWebView |
| `.htm` | HTML | O | HTMLWebView |

파일 형식 추가 시 변경 지점:
1. `FolderScanner.supportedExtensions`
2. `FolderScanner.fileType(for:)`
3. `NoteDetailView` 뷰어 분기
