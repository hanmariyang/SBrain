# v0.6.2 Hotfixes — Execution Log

Type: T6 – Execution Log
Owner: gicheol
Status: Done
Last Updated: 2026-03-24

---

## 수정 사항

### 1. DB 테이블 리스트 중복 표시 제거
- **증상**: database 모드에서 ExplorerPanel과 DatabaseBrowserView가 동시에 테이블 리스트 렌더링
- **원인**: ContentView에서 `HSplitView { DatabaseBrowserView() + DBDetailView() }` 구조
- **수정**: DB 연결 후 메인 영역에 `DBDetailView()`만 표시, ExplorerPanel이 테이블 네비게이션 전담
- **파일**: `ContentView.swift`

### 2. Sparkle SUFeedURL Info.plist 누락
- **증상**: 앱 실행 시 `SUFeedURL key` 에러, 업데이트 확인 불가
- **원인**: Sparkle 키(`SUFeedURL`, `SUPublicEDKey` 등)가 XcodeGen `settings.base`(빌드 설정)에만 있고 Info.plist에 미포함
- **수정**: `GENERATE_INFOPLIST_FILE: YES` 제거, XcodeGen `info.properties`로 이동하여 Info.plist에 정상 생성
- **파일**: `project.yml`, `SBrain/Info.plist`

### 3. 앱 아이콘 logo03 변경
- **증상**: logo01 → logo03으로 변경 요청
- **수정**: logo03.png에서 체커보드 배경을 cream(#FAF8F5)으로 교체, 로고 크롭하여 꽉 차게 리사이징
- **파일**: `Assets.xcassets/AppIcon.appiconset/icon_*.png`
