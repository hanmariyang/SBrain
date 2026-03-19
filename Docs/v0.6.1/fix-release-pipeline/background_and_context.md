# Release Pipeline Fix — Background & Context

Type: T2 – Background & Context
Owner: gicheol
Status: In Progress
Last Updated: 2026-03-19

---

## 문제 정의

v0.6.0 배포 시 GitHub Actions 릴리즈 워크플로우가 실패하여 Sparkle 자동 업데이트 파이프라인이 동작하지 않음.

### 증상
- 기존 v0.5.0 앱에서 업데이트 확인 시 아무 반응 없음
- `appcast.xml`이 빈 스캐폴드 상태 (릴리즈 항목 없음)

### 근본 원인

1. **Xcode 프로젝트 포맷 불일치**
   - `project.yml`에 `xcodeVersion: "16.0"` 설정 → XcodeGen이 프로젝트 포맷 77로 생성
   - CI 러너 `macos-14`는 Xcode 15.x 탑재 → 포맷 77 읽기 불가
   - 에러: `"The project cannot be opened because it is in a future Xcode project file format (77)"`

2. **GitHub Actions 권한 부족**
   - 기본 `GITHUB_TOKEN` 권한이 `contents: read`
   - step 13에서 `git push origin main` (appcast.xml 커밋) 시 write 권한 필요

### 영향 범위
- Sparkle 자동 업데이트 전체 미동작
- GitHub Release 미생성
- DMG 배포 불가
