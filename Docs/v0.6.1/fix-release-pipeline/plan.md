# Release Pipeline Fix — Plan

Type: T3 – Plan / Design
Owner: gicheol
Status: In Progress
Last Updated: 2026-03-19

---

## 수정 사항

### 1. CI 러너 업그레이드
- `runs-on: macos-14` → `runs-on: macos-15`
- macOS 15 러너는 Xcode 16.x 탑재 → 프로젝트 포맷 77 지원

### 2. GitHub Actions 권한 추가
- `permissions: contents: write` 추가
- appcast.xml 커밋 + GitHub Release 생성에 필요

### 3. Sparkle 앱 시작 시 업데이트 확인 강화
- `SUAutomaticallyUpdate` Info.plist 키 추가 (자동 다운로드+설치)
- `SUEnableAutomaticChecks` 기본 활성화
- 앱 최초 실행 시 Sparkle 업데이트 프롬프트 없이 자동 확인

## 검증 계획
- release.yml 수정 후 v0.6.1 태그 push → CI 성공 확인
- appcast.xml에 릴리즈 항목 생성 확인
- GitHub Release에 DMG 업로드 확인
