# Plan: SBrain v0.2.0 — Multi-Project & 3D Brain Map

Type: T3 – Plan / Design
Owner: gicheol
Status: Done
Last Updated: 2026-03-14

---

## 1. Goal

SBrain을 단일 폴더 뷰어에서 **멀티 프로젝트 통합 탐색기**로 확장하고,
Brain Map을 2D 평면에서 **3D 구체(Sphere) 시각화**로 전환한다.

**성공 기준**
1. 복수 프로젝트 폴더를 동시에 추가·탐색 가능
2. Brain Map이 3D 구체 위에서 자동 회전하며 원근감 제공
3. 프로젝트별 탭 필터링으로 특정 프로젝트만 볼 수 있음
4. MD/HTML 파일을 시각적으로 구분 가능
5. 클릭/드래그/줌 제스처가 충돌 없이 동작

---

## 2. Scope

### In Scope

- 멀티 프로젝트 상태 관리 (`[ProjectFolder]`)
- 프로젝트 탭 UI + 필터링 (All / 개별 프로젝트)
- 3D 구체 레이아웃 (Fibonacci Sphere 분포)
- 3D→2D 원근 투영 (perspective projection)
- 자동 회전 + 드래그 회전 + 스크롤 줌
- MD/HTML 파일 시각 구분 (원형 vs 사각형, 시안 vs 오렌지)
- HTML 파일 뷰어 지원
- 제스처 충돌 해결

### Out of Scope

- 백엔드 변경 (Django API는 v0.1.0 그대로)
- 프로젝트 간 크로스 시냅스
- 프로젝트 순서 드래그

---

## 3. Background (v0.1.0의 문제점)

### 문제 1: 단일 프로젝트만 지원
- 한 번에 하나의 폴더만 열 수 있어 여러 프로젝트를 비교·탐색 불가

### 문제 2: 2D 레이아웃 한계
- 노드가 사각형 영역에 갇혀 밀집됨
- 규모와 크기 가늠 불가, 선택 어려움

### 문제 3: 라벨 혼잡
- 모든 노드에 항상 라벨을 표시하면 텍스트가 겹쳐 가독성 저하

### 문제 4: 제스처 충돌
- DragGesture가 TapGesture를 가로채 클릭 불가
- Brain Map ↔ List View 전환 시에도 동일 문제

### 문제 5: 파일 형식 미구분
- MD와 HTML 파일이 동일한 형태로 표시

---

## 4. Design Decisions

### DD1: 멀티 프로젝트 아키텍처

```
NoteStore
├── projects: [ProjectFolder]        ← 복수 프로젝트
├── selectedProjectId: UUID?         ← 필터링 (nil = All)
├── brainGraph: BrainGraph?          ← 전체 병합 그래프
├── filteredBrainGraph: BrainGraph?  ← 선택 프로젝트만 필터링 (computed)
└── visibleProjects: [ProjectFolder] ← 표시할 프로젝트 목록 (computed)
```

- `selectedProjectId == nil` → 모든 프로젝트 표시
- 탭 클릭 → 해당 프로젝트만 표시 (재클릭 → All 복귀)

### DD2: 3D 구체 레이아웃 (Fibonacci Sphere)

**기존 (v0.1.0)**: 2D 원형 배치 → 사각형에 갇힌 느낌
**변경 (v0.2.0)**: 3D Fibonacci Sphere

```
피보나치 스파이럴 공식:
  y = 1 - (i / (n-1)) * 2        ← 위도: -1 ~ +1 균등
  θ = 2π * i / φ                  ← 경도: 황금비 간격
  x = cos(θ) * √(1 - y²)
  z = sin(θ) * √(1 - y²)
```

장점:
- 구체 표면에 균등 분포 → 밀집/공백 없음
- 회전 시 모든 방향에서 자연스러운 배치
- 노드 수에 관계없이 일정한 간격

### DD3: 원근 투영 (Perspective Projection)

```
screenX = centerX + (x * fov / (fov + z)) * scale * zoom
screenY = centerY - (y * fov / (fov + z)) * scale * zoom
```

- 가까운 노드(z > 0): 크고, 밝고, 불투명
- 먼 노드(z < 0): 작고, 어둡고, 투명
- Painter's Algorithm: 먼 노드부터 그림 → 겹침 자연 처리

### DD4: 자동 회전 + 수동 회전

- **자동**: Y축 0.08 rad/sec 연속 회전 (생동감)
- **드래그**: 좌우 = yaw(Y축), 상하 = pitch(X축), 감도 0.005
- **줌**: 스크롤 휠, 범위 0.4x ~ 3.0x
- **pitch 제한**: ±90° (뒤집힘 방지)

### DD5: MD/HTML 시각 구분

| 파일 형식 | 노드 형태 | 색상 범위 | 호버 배지 |
|-----------|----------|----------|----------|
| Markdown (.md) | 원형 (Circle) | 시안-퍼플 (hue 0.5~0.8) | 시안 |
| HTML (.html/.htm) | 둥근 사각형 (Rounded Rect) | 오렌지 (hue 0.08~0.13) | 오렌지 |

### DD6: 제스처 충돌 해결

- `.simultaneousGesture()` 사용 → 제스처 간 독립 동작
- `DragGesture(minimumDistance: 5)` → 5px 이상 이동 시에만 드래그 인식
- 5px 미만 = 탭으로 판정

### DD7: 라벨 정책

- **호버/선택 시에만** 파일명 + 형식 배지 표시
- 프로젝트 클러스터 라벨 제거 (3D 회전 시 위치 불안정)
- 깔끔한 기본 상태 → 상호작용으로 상세 정보 확인

---

## 5. Structure / Flow

### 5.1 멀티 프로젝트 흐름

```
[Cmd+O] → NSOpenPanel (allowsMultipleSelection)
        → addProject(path:) × N
        → FolderScanner.scan() × N
        → ProjectFolder 생성 × N
        → LocalGraphBuilder.build(from: allRoots)  ← 3D 좌표
        → BrainGraph (neurons with x,y,z + synapses)
        → BrainCanvas3D (3D→2D 투영 + 렌더링)
```

### 5.2 프로젝트 필터링 흐름

```
[프로젝트 탭 클릭]
  → noteStore.selectProject(id)
  → selectedProjectId 변경
  → filteredBrainGraph (computed)
     → neuron.id.hasPrefix(project.path) 필터
     → synapse source/target 모두 해당 프로젝트인 것만
  → BrainCanvas3D 자동 갱신
  → FolderTreeView: visibleProjects만 표시
```

### 5.3 3D 렌더링 파이프라인

```
TimelineView (30fps)
  → 매 프레임:
    1. drawBackground (우주 그라디언트)
    2. drawStarfield (별 파티클 30개)
    3. project() → 모든 뉴런 3D→2D 투영
    4. sort by depth (Painter's Algorithm)
    5. drawSynapses (깊이 기반 투명도)
    6. drawNeurons (깊이 기반 크기/투명도)
    7. drawHoverLabel (최상위)
```

---

## 6. File Changes (v0.1.0 → v0.2.0)

| File | Change Type | Description |
|------|-------------|-------------|
| `Models/Note.swift` | Modified | Neuron에 `z: Double` 추가 |
| `Services/NoteStore.swift` | Modified | `[ProjectFolder]`, `selectedProjectId`, `filteredBrainGraph`, `visibleProjects` |
| `Services/LocalGraphBuilder.swift` | Rewritten | 2D 원형 → 3D Fibonacci Sphere |
| `Services/FolderScanner.swift` | Modified | `supportedExtensions`, `FileType`, `fileType(for:)` |
| `Views/BrainMapView.swift` | Rewritten | 2D Canvas → 3D 원근 투영 + 자동 회전 |
| `Views/ContentView.swift` | Modified | `ProjectTabBar`, `AllProjectsTab`, 필터링 UI |
| `Views/NoteListView.swift` | Modified | `visibleProjects` 기반 표시 |
| `Views/NoteDetailView.swift` | Modified | MD/HTML 뷰어 분기 |
| `SBrainApp.swift` | Modified | 메뉴 "프로젝트 추가..." |

---

## 7. Open Issues

- [ ] 프로젝트 필터링 시 3D 좌표 재계산 (현재는 전체 그래프에서 필터만 적용)
- [ ] 프로젝트 간 크로스 시냅스 (유사도 기반 연결)
- [ ] 프로젝트 순서 변경 (드래그)
- [ ] 3D 회전 관성(inertia) 효과
- [ ] 줌 시 회전 중심점 조정
