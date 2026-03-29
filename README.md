# SBrain — Second Brain

> Your local markdown files as a **3D brain map** — explore connections like neurons and synapses.

SBrain indexes your notes as **Neurons**, links related notes as **Synapses**, and renders everything in a 3D brain you can rotate, zoom, and search through.  Now with **cloud sync** and an **iOS companion app**.

![macOS](https://img.shields.io/badge/macOS-14.0+-black?logo=apple)
![iOS](https://img.shields.io/badge/iOS-17.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python)
![Django](https://img.shields.io/badge/Django-5.0-green?logo=django)

---

## Brain Metaphor

| Traditional | SBrain | Description |
|------------|--------|-------------|
| Note | **Memory** | A single markdown/HTML file |
| Chunk | **Neuron** | A text segment with its embedding vector |
| Connection | **Synapse** | Embedding similarity link between neurons |
| Indexing | **Memorize** | Scan folders and store in brain |
| Search | **Recall** | Retrieve related memories by meaning |

## Features

### Core
- **3D Brain Map** — Neurons distributed on a Fibonacci Sphere. Auto-rotate, drag-rotate, zoom, pan. Perspective depth rendering.
- **Semantic Recall** — Vector similarity search powered by Anthropic Voyage-3. Search by meaning, not keywords.
- **Multi-Project** — Open multiple note folders simultaneously. All merge into one unified brain map.
- **MD/HTML Support** — Markdown (circle, cyan) and HTML (square, orange) visual distinction.
- **Folder Tree** — Browse local folder structure. Per-project sections.
- **Document Viewer** — WKWebView-based markdown rendering + native HTML display.
- **Local-First** — Instant 3D graph from folder scan. Auto-upgrade when backend embeddings complete.

### v0.8.0+
- **Integrated Terminal** — Built-in terminal (SwiftTerm) with bottom panel & full-screen mode.
- **Database Browser** — Connect to external databases and explore tables in-app.
- **Slack & Calendar** — Connect Slack workspace and Google Calendar alongside your notes.
- **File Change Detection** — FSEvents-based real-time file monitoring with partial re-indexing.
- **Auth Persistence** — Slack/Calendar authentication persists across app restarts.

### v0.9.0 (Current)
- **Cloud Sync** — Local files stay on your Mac. Content mirrors to Railway (PostgreSQL) for cross-device access.
- **iOS Companion** — Read-only iPhone app with 3D Brain Map (touch gestures), note viewer, and search.
- **JWT Authentication** — Secure cloud API access with access/refresh tokens.
- **Auto Updates** — Sparkle 2 framework with Ed25519 signed updates.
- **TelemetryDeck** — Privacy-first analytics for usage insights.

## Architecture

```
┌─ macOS (Local, Primary) ────────────────────────┐
│  SwiftUI App                                     │
│  ├── 3D Brain Map (Canvas + TimelineView 30fps)  │
│  ├── NoteStore (State) + FileMonitor (FSEvents)  │
│  ├── Terminal, DB Browser, Slack, Calendar        │
│  ├── APIClient → localhost:8765 (Local Django)   │
│  └── SyncManager → Railway (Cloud Push)          │
│                                                   │
│  Django 5 Backend (Child Process)                 │
│  ├── sqlite-vec (Vector DB) + Voyage-3 Embedding │
│  └── brain.db (Local SQLite)                     │
└──────────────────────┬────────────────────────────┘
                       │ Sync Push
                       ▼
┌─ Railway (Cloud Mirror) ────────────────────────┐
│  Django 5 + PostgreSQL                           │
│  ├── Notes, Chunks (content mirror)              │
│  ├── JWT Auth (SimpleJWT)                        │
│  └── REST API: /api/notes/, /api/search/, etc.   │
└──────────────────────┬────────────────────────────┘
                       │ REST API
                       ▼
┌─ iOS (Read-Only Client) ────────────────────────┐
│  SwiftUI App                                     │
│  ├── 3D Brain Map (Touch: drag, pinch, tap)      │
│  ├── Note Viewer + Search (Recall)               │
│  └── JWT Auth → Railway API                      │
└──────────────────────────────────────────────────┘
```

## Getting Started

### Prerequisites

- macOS 14.0+ / iOS 17.0+
- Xcode 16+
- Python 3.11
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [Anthropic API Key](https://console.anthropic.com/)

### 1. Clone

```bash
git clone https://github.com/your-username/SBrain.git
cd SBrain
```

### 2. Backend Setup

```bash
python3.11 -m venv venv
source venv/bin/activate
pip install -r backend/requirements.txt

cp backend/.env.example backend/.env
# Edit backend/.env — set ANTHROPIC_API_KEY
```

### 3. Database

```bash
cd backend && python manage.py migrate && cd ..
```

### 4. Build & Run

```bash
cd app
xcodegen generate
open SBrain.xcodeproj
# Cmd + R to run (macOS target)
# Select SBrain-iOS scheme for iOS Simulator
```

The macOS app automatically starts the Django backend as a child process.

### 5. Usage

1. Launch app → click **Add Project** (multiple folders supported)
2. Select folders containing `.md` / `.html` files
3. **3D Brain Map** renders instantly — drag to rotate, scroll to zoom
4. Click a neuron → view document in detail panel
5. Use **Recall** search bar for semantic search
6. Enable Cloud Sync in Settings to mirror notes to iOS

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/ingest/` | Memorize — index a folder |
| `GET` | `/api/notes/` | List memories |
| `GET` | `/api/notes/{id}/` | Memory detail |
| `POST` | `/api/search/` | Recall — vector search |
| `GET` | `/api/status/` | Memorize progress |
| `GET` | `/api/graph/?threshold=0.5` | Brain Graph (neurons + synapses) |
| `POST` | `/api/sync/push/` | Cloud sync push (JWT required) |
| `POST` | `/api/auth/token/` | JWT token obtain |
| `POST` | `/api/auth/token/refresh/` | JWT token refresh |
| `POST` | `/api/auth/register/` | User registration |

## Project Structure

```
SBrain/
├── app/                           # SwiftUI App (macOS + iOS)
│   ├── project.yml                # XcodeGen config (multi-target)
│   └── SBrain/
│       ├── SBrainApp.swift        # macOS entry point
│       ├── Models/
│       ├── Views/                 # macOS views
│       ├── Services/              # APIClient, NoteStore, SyncManager, etc.
│       ├── Theme/                 # Design tokens (SB namespace)
│       └── iOS/                   # iOS-specific views + entry point
├── backend/                       # Django REST Backend
│   ├── config/                    # Django settings, URLs
│   └── notes/                     # Core logic (ingest, search, graph, sync)
├── landing/                       # Landing page (static HTML)
└── Docs/                          # T-type documentation system
    ├── Global Policy/             # T5 policies
    └── v{X.Y.Z}/                  # Versioned T2~T4, T7 docs
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Anthropic API key | (required) |
| `EMBEDDING_MODEL` | Embedding model | `voyage-3` |
| `DB_PATH` | Local database path | `./brain.db` |
| `DJANGO_SECRET_KEY` | Django secret key | (required) |
| `DJANGO_DEBUG` | Debug mode | `True` |
| `PORT` | Backend port | `8765` |
| `DATABASE_URL` | PostgreSQL URL (Railway) | — |

## Version History

| Version | Description |
|---------|-------------|
| v0.1.0 | MVP — Single folder, 2D Brain Map, MD viewer |
| v0.2.0 | Multi-project, 3D Sphere Brain Map, HTML support |
| v0.5.0 | Integrated terminal, personal workspace |
| v0.6.0 | UI redesign (design tokens, SB namespace) |
| v0.7.0 | Slack & Calendar integration |
| v0.8.0 | Architecture improvement — auth persistence, file change detection, partial re-indexing |
| v0.9.0 | Cloud sync (Railway + PostgreSQL), iOS companion app, JWT auth, TelemetryDeck |

## License

MIT License
