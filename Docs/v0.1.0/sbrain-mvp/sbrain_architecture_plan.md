# Plan: SBrain Architecture & Rendering Policy

Type: T3 – Plan / Design
Owner: gicheol
Status: Superseded by v0.2.0
Last Updated: 2026-03-14
Superseded By: Docs/v0.2.0/multi-project-3d/sbrain_v0.2.0_plan.md

---

## 1. Goal

SBrain의 아키텍처 설계 기준과 렌더링 정책을 정의한다.

**성공 기준**
1. 멀티 프로젝트 환경에서 500+ 노드를 30fps로 렌더링
2. 백엔드 불가용 상태에서도 기본 기능(파일 탐색, 뷰어, 로컬 그래프) 정상 동작
3. 신규 파일 형식 추가 시 변경 지점이 3곳 이하

---

## 2. Scope

### In Scope

- SwiftUI macOS 앱 렌더링 아키텍처
- 멀티 프로젝트 상태 관리
- Brain Map 성능 정책
- 파일 뷰어 확장 구조

### Out of Scope

- 백엔드(Django) 아키텍처
- 웹 클라이언트
- CI/CD

---

## 3. User Scenarios

### Scenario 1: 멀티 프로젝트 탐색

```
1. 사용자가 Cmd+O로 프로젝트 폴더 추가 (복수 선택 가능)
2. 좌측 사이드바에 프로젝트별 탭 표시
3. Brain Map에 모든 프로젝트가 클러스터로 분리 표시
4. 각 클러스터에 프로젝트명 라벨 표시
5. 각 노드에 파일명 라벨 상시 표시
```

### Scenario 2: 프로젝트 제거

```
1. 프로젝트 탭에서 X 버튼 클릭
2. 해당 프로젝트의 뉴런/시냅스가 Brain Map에서 제거
3. 나머지 프로젝트 그래프 자동 재배치
```

---

## 4. Design Principles

1. **Local-First**: 폴더 선택 즉시 로컬 데이터만으로 UI 구성. 백엔드는 비동기 보강.
2. **Single Canvas**: Brain Map은 단일 Canvas에서 렌더링. 개별 SwiftUI View 생성 금지.
3. **WKWebView 통일**: 모든 문서 뷰어는 WKWebView 기반. Markdown은 파서 → HTML 변환.
4. **시냅스 제한**: 최대 500개. 같은 폴더 8개 초과 시 링+허브 구조.
5. **프로젝트 독립성**: 각 프로젝트의 그래프 영역은 독립적으로 계산 후 병합.

---

## 5. Structure / Flow

### 5.1 상태 관리

```
NoteStore (ObservableObject)
├── projects: [ProjectFolder]      ← 멀티 프로젝트
├── brainGraph: BrainGraph?        ← 전체 프로젝트 병합 그래프
├── selectedFilePath / Content     ← 현재 선택 파일
└── searchResults / Query          ← Recall 검색
```

### 5.2 렌더링 파이프라인

```
[폴더 추가] → FolderScanner.scan()
           → ProjectFolder 생성
           → LocalGraphBuilder.build(from: allRoots)
           → BrainGraph (neurons + synapses)
           → BrainCanvas (Canvas + TimelineView)
```

### 5.3 파일 뷰어 분기

```
selectedFilePath → FolderScanner.fileType(for:)
  .markdown → MarkdownWebView (파서 → HTML → WKWebView)
  .html     → HTMLWebView (직접 WKWebView 로드, baseURL 설정)
```

---

## 6. Decision Points

### DP1: Brain Map 라벨 표시 방식

| 선택지 | 설명 |
|--------|------|
| A) 호버 시에만 표시 | 깔끔하지만 노드 구분 불가 |
| **B) 항상 표시 (선택)** | 작은 폰트로 상시 표시 + 호버 시 상세 표시 |

→ **B 선택**: 노드 수가 적을 때도 맥락 파악 가능

### DP2: 멀티 프로젝트 그래프 배치

| 선택지 | 설명 |
|--------|------|
| **A) 프로젝트별 영역 분리 (선택)** | 각 프로젝트가 캔버스의 독립 영역 차지 |
| B) 전체 통합 배치 | 프로젝트 구분 어려움 |

→ **A 선택**: 프로젝트 간 시각적 구분 명확

---

## 7. Open Issues

- [ ] 프로젝트 간 유사도 시냅스 (크로스 프로젝트 연결) 미구현
- [ ] 프로젝트 순서 변경 (드래그) 미구현
- [ ] 프로젝트별 색상 고정 방식 미정 (현재 해시 기반)
