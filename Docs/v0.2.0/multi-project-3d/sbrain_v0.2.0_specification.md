# Specification: SBrain v0.2.0 Data Model & State

Type: T4 – Specification
Owner: gicheol
Status: Done
Last Updated: 2026-03-14

---

## 1. Purpose

v0.2.0에서 변경/추가된 데이터 모델, 상태 관리, UI 컴포넌트를 명세한다.

---

## 2. Data Model Changes

### Neuron (변경)

| Field | Type | v0.1.0 | v0.2.0 | Note |
|-------|------|--------|--------|------|
| id | String | O | O | 파일 절대 경로 |
| filename | String | O | O | |
| preview | String | O | O | 80자 미리보기 |
| x | Double | O | O | 3D X 좌표 (-1 ~ +1) |
| y | Double | O | O | 3D Y 좌표 (-1 ~ +1) |
| **z** | **Double** | **-** | **O** | **3D Z 좌표 (-1 ~ +1), 기본값 0.5** |
| chunkCount | Int | O | O | |
| projectTag | String | O | O | 소속 프로젝트명 |

### ProjectFolder (신규)

| Field | Type | Note |
|-------|------|------|
| id | UUID | auto-generated |
| path | String | 프로젝트 절대 경로 |
| name | String | 폴더명 |
| rootFolder | FolderNode? | 스캔된 트리 |

### FolderScanner.FileType (신규)

```swift
enum FileType {
    case markdown
    case html
}
```

### FolderScanner.supportedExtensions

```swift
static let supportedExtensions: Set<String> = ["md", "html", "htm"]
```

---

## 3. State Management (NoteStore)

### Published Properties

| Property | Type | Description |
|----------|------|-------------|
| projects | [ProjectFolder] | 등록된 프로젝트 목록 |
| **selectedProjectId** | **UUID?** | **필터링 대상 (nil = All)** |
| selectedFilePath | String? | 선택된 파일 경로 |
| selectedFileContent | String? | 선택된 파일 내용 |
| brainGraph | BrainGraph? | 전체 병합 그래프 |
| searchResults | [SearchResult] | Recall 결과 |
| searchQuery | String | 검색어 |
| isSearching | Bool | 검색 진행 중 |
| ingestStatus | IngestStatus? | Memorize 상태 |
| isIngesting | Bool | Memorize 진행 중 |

### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| **selectedProject** | **ProjectFolder?** | **selectedProjectId에 해당하는 프로젝트** |
| **filteredBrainGraph** | **BrainGraph?** | **선택 프로젝트 뉴런/시냅스만 필터링** |
| **visibleProjects** | **[ProjectFolder]** | **선택 프로젝트만 또는 전체** |
| totalDocCount | Int | 전체 문서 수 |
| allRootFolders | [FolderNode] | 모든 프로젝트 루트 |
| hasProjects | Bool | 프로젝트 존재 여부 |

### Methods

| Method | Description |
|--------|-------------|
| addFolder() | NSOpenPanel으로 복수 폴더 선택·추가 |
| addProject(path:) | 단일 프로젝트 추가 + 스캔 + 그래프 재구축 |
| removeProject(at:) | 인덱스로 프로젝트 제거 |
| **selectProject(_:)** | **필터링 토글 (같은 ID 재클릭 → nil)** |
| restoreProjects() | UserDefaults에서 복원 |
| rebuildGraph() | 전체 프로젝트 그래프 재구축 |
| selectFile(path:) | 파일 선택 + 내용 로드 |
| recall() | 벡터 검색 실행 |

### 필터링 로직

```swift
var filteredBrainGraph: BrainGraph? {
    guard let graph = brainGraph else { return nil }
    guard let project = selectedProject else { return graph }

    let projectPrefix = project.path
    let filteredNeurons = graph.neurons.filter { $0.id.hasPrefix(projectPrefix) }
    let neuronIds = Set(filteredNeurons.map(\.id))
    let filteredSynapses = graph.synapses.filter {
        neuronIds.contains($0.source) && neuronIds.contains($0.target)
    }
    return BrainGraph(neurons: filteredNeurons, synapses: filteredSynapses)
}

func selectProject(_ id: UUID?) {
    selectedProjectId = (selectedProjectId == id) ? nil : id
}
```

### Persistence

| Key | Storage | Description |
|-----|---------|-------------|
| `SBrain.projectPaths` | UserDefaults | `[String]` — 프로젝트 경로 배열 |

---

## 4. 3D Layout Algorithm

### Fibonacci Sphere Distribution

```
Input:  N files (collected from all project folders)
Output: N points on unit sphere

For each file i (0..N-1):
    y  = 1 - (i / (N-1)) * 2
    r  = √(1 - y²)
    θ  = 2π * i / φ          (φ = golden ratio ≈ 1.618)
    x  = cos(θ) * r
    z  = sin(θ) * r
```

### Multi-Project Region Offsets

| Projects | Region Center | Region Radius |
|----------|--------------|---------------|
| 1 | (0, 0, 0) | 1.0 |
| 2 | ±0.5 on XZ circle | 0.6 / √2 ≈ 0.42 |
| 3 | 120° apart on XZ circle | 0.6 / √3 ≈ 0.35 |
| N | 360°/N apart on XZ circle, r=0.28 | 0.30 / √N |

### Perspective Projection (3D → 2D)

```
Input:  (x, y, z) in world space, rotationX, rotationY, time
Output: (screenX, screenY, depth, scale)

1. Auto-rotate:  totalYaw = rotationY + time * 0.08
2. Y-axis rotation:
     rx = x * cos(yaw) + z * sin(yaw)
     rz = -x * sin(yaw) + z * cos(yaw)
3. X-axis rotation (pitch):
     ry2 = ry * cos(pitch) - rz * sin(pitch)
     rz2 = ry * sin(pitch) + rz * cos(pitch)
4. Perspective:
     fov = 3.0
     scale = fov / (fov + rz2)
     screenX = center.x + rx * scale * width * 0.35 * zoom
     screenY = center.y - ry2 * scale * height * 0.35 * zoom
5. Depth:
     normalizedDepth = (rz2 + 1.5) / 3.0   (0 = far, 1 = near)
```

---

## 5. UI Components

### ProjectTabBar

| Component | Description |
|-----------|-------------|
| AllProjectsTab | "All" 탭 (brain 아이콘), selectedProjectId == nil일 때 활성 |
| ProjectTab | 프로젝트별 탭 (색상 도트 + 이름 + 파일 수 + X 버튼) |
| + 버튼 | 프로젝트 추가 |

### ProjectTab States

| State | Background | Border |
|-------|-----------|--------|
| Default | white 4% | projectColor 30% |
| Hover | white 8% | projectColor 30% |
| **Active** | **projectColor 15%** | **projectColor 50%** |

### BrainCanvas3D Rendering Order

```
1. Background (우주 그라디언트: top→mid→bottom)
2. Starfield (30개 별, twinkle 효과)
3. Synapses (깊이 평균으로 투명도 결정)
4. Neurons (depth sort → far first, Painter's Algorithm)
   - Outer glow (depth 기반 크기/투명도)
   - Core shape (MD=circle, HTML=rounded rect)
   - Center dot/highlight
5. Hover label (최상위, 검정 배경 + 색상 테두리)
```

### Neuron Depth Rendering

| Depth | Size Multiplier | Opacity | Glow |
|-------|----------------|---------|------|
| 0.0 (far) | 0.5x | 0.15 | minimal |
| 0.5 (mid) | 0.9x | 0.55 | moderate |
| 1.0 (near) | 1.3x | 0.90 | full |

---

## 6. Interaction Specification

### Gestures

| Gesture | Action | Implementation |
|---------|--------|----------------|
| Tap | 뉴런 선택 | `.onTapGesture` → hitTest3D |
| Hover | 뉴런 하이라이트 + 라벨 | `.onContinuousHover` → hitTest3D |
| Drag | 3D 회전 (yaw/pitch) | `.simultaneousGesture(DragGesture(minimumDistance: 5))` |
| Scroll | 줌 인/아웃 | NSView `scrollWheel` → zoom 0.4~3.0 |

### Hit Testing (3D)

```
1. 현재 시간으로 모든 뉴런 3D→2D 투영
2. depth 내림차순 정렬 (가까운 것 우선)
3. 클릭 좌표와 투영 좌표 거리 계산
4. radius² 이내 첫 번째 뉴런 반환
5. 최소 hitRadius: 14px
```

---

## 7. Supported File Types

| Extension | FileType | Node Shape | Color Range | Viewer |
|-----------|----------|-----------|-------------|--------|
| `.md` | .markdown | Circle | Cyan-Purple (hue 0.5~0.8) | MarkdownWebView |
| `.html` | .html | Rounded Rect | Orange (hue 0.08~0.13) | HTMLWebView |
| `.htm` | .html | Rounded Rect | Orange (hue 0.08~0.13) | HTMLWebView |

---

## 8. Constraints

- 시냅스 최대 600개 (v0.1.0: 500개)
- 같은 폴더 8개 초과 시 링+허브 구조
- TimelineView 30fps (v0.1.0: 24fps)
- Pitch 제한: ±90° (gimbal lock 방지)
- Zoom 범위: 0.4x ~ 3.0x
- Drag 최소 거리: 5px (탭 오인식 방지)
- Perspective FOV: 3.0 (자연스러운 원근감)
- Auto-rotation: 0.08 rad/sec (약 12초/회전)
