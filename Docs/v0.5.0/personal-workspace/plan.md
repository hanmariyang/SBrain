# Plan: Personal Workspace — 기본 폴더 + 문서 편집 + 저장하기

Type: T3 – Plan / Design
Owner: gicheol
Status: Done
Last Updated: 2026-03-17

---

## 1. Goal

- SBrain 전용 기본 폴더에서 마크다운/HTML 문서를 생성·편집·삭제할 수 있다
- 프로젝트 폴더의 파일을 기본 폴더로 복사(저장하기)하여 개인 지식 저장소를 구축한다
- 기본 폴더를 기존 프로젝트와 동일하게 Brain Map·검색에 통합한다

성공 기준:
1. 기본 폴더에서 새 마크다운 파일 생성 및 편집이 가능하다
2. 프로젝트 폴더 파일에 "저장하기" 버튼이 표시되고 기본 폴더로 복사된다
3. 기본 폴더가 Brain Map 및 Recall 검색에 통합된다

## 2. Scope

### In Scope
- 기본 폴더 자동 생성 (`~/Documents/SBrain/`)
- 기본 폴더 경로 설정 변경
- 앱 내 마크다운 텍스트 에디터 (raw 편집 + 미리보기)
- 새 문서 생성, 편집, 저장
- 외부 에디터 열기 버튼
- 프로젝트 파일 → 기본 폴더 복사 (프로젝트명 하위 폴더)
- 기본 폴더를 특수 프로젝트로 자동 등록 (Brain Map 통합)

### Out of Scope
- WYSIWYG 리치 에디터
- 양방향 동기화
- 파일 삭제 확인 없는 즉시 삭제
- HTML 에디터 (HTML은 뷰어만)

## 3. User Scenarios

### Scenario 1: 새 문서 작성
1. 사용자가 기본 폴더 탭에서 "새 문서" 버튼 클릭
2. 파일명 입력 다이얼로그 표시
3. 빈 마크다운 파일 생성, 에디터 패널에서 편집
4. 저장 (Cmd+S 또는 자동 저장)

### Scenario 2: 프로젝트 파일을 기본 폴더로 복사
1. 프로젝트 폴더에서 파일 선택, 상세 뷰에 표시
2. "저장하기" 버튼 클릭
3. `~/Documents/SBrain/{프로젝트명}/파일명.md`로 복사
4. 복사 완료 토스트 표시

### Scenario 3: 외부 에디터로 열기
1. 기본 폴더 또는 프로젝트 파일 상세 뷰에서 "외부 에디터" 버튼 클릭
2. macOS 기본 앱으로 파일 열기 (`NSWorkspace.shared.open`)

## 4. Design Principles

1. **기본 폴더 = 특수 프로젝트**: 기존 ProjectFolder 인프라 재사용
2. **읽기/쓰기 구분**: 프로젝트 폴더는 읽기 전용, 기본 폴더만 쓰기 가능
3. **일회성 복사**: 저장하기는 스냅샷 복사, 원본과 독립
4. **최소 에디터**: raw 마크다운 편집 + 미리보기 토글, 리치 에디터 불필요
5. **Brain 메타포 유지**: 기본 폴더 = "내 기억", 프로젝트 폴더 = "외부 기억"

## 5. Structure / Flow

### 5.1 기본 폴더 관리

```
NoteStore
├── baseFolder: BaseFolder?          ← 새로 추가
│   ├── path: String                 (~/Documents/SBrain/)
│   ├── rootFolder: FolderNode?
│   └── isWritable: true
├── projects: [ProjectFolder]        ← 기존 (읽기 전용)
```

### 5.2 저장 경로 구조

```
~/Documents/SBrain/
├── 내가 직접 작성한 문서.md
├── EduOps/                          ← 프로젝트에서 복사한 파일
│   ├── README.md
│   └── api_spec.md
└── SBrain/
    └── architecture.md
```

### 5.3 UI 구성

- **ProjectTabBar**: 기본 폴더 탭 (고정, 첫 번째 위치, 특수 아이콘)
- **MemoryDetailView**: 기본 폴더 파일 선택 시 편집 모드 활성화
  - 편집/미리보기 토글
  - 저장 버튼 (Cmd+S)
  - 외부 에디터 열기 버튼
- **MemoryDetailView**: 프로젝트 파일 선택 시 "저장하기" 버튼 추가

### 5.4 수정 파일 목록

| 파일 | 변경 내용 |
|------|-----------|
| `NoteStore.swift` | baseFolder 관리, 파일 생성/저장/복사 메서드 |
| `ContentView.swift` | 기본 폴더 탭, 새 문서 버튼 |
| `MemoryDetailView.swift` | 편집 모드, 저장하기 버튼, 외부 에디터 |
| `Note.swift` | BaseFolder 모델 (또는 ProjectFolder 확장) |

## 6. Decision Points

| 선택지 | 추천 | 근거 |
|--------|------|------|
| 기본 폴더 위치 | `~/Documents/SBrain/` | macOS 관례, 접근성 |
| 복사 구조 | `기본폴더/{프로젝트명}/` | 출처 추적, 이름 충돌 방지 |
| 에디터 | raw 텍스트 + 미리보기 | 구현 비용 낮음, 핵심 가치는 탐색 |
| 자동 저장 | 편집 중 3초 debounce | 사용자 편의, 데이터 손실 방지 |

## 7. Open Issues

- 기본 폴더 삭제 시 앱 동작 (재생성 or 경고)
- 동일 파일명 복사 시 덮어쓰기 vs 번호 부여
