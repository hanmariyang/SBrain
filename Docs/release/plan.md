# Plan: macOS App Release Pipeline

Type: T3 – Plan / Design
Owner: gicheol
Status: Draft
Last Updated: 2026-03-18

---

## 1. Goal

macOS 앱을 서명·공증된 `.dmg` 파일로 배포하고, 출시 후 자동 업데이트를 지원하는 릴리즈 파이프라인을 구축한다.

**성공 기준:**
1. `git tag v1.0.0 && git push --tags` 만으로 서명된 `.dmg`가 GitHub Release에 게시됨
2. 사용자가 GateKeeper 경고 없이 `.dmg`를 열어 설치 가능
3. 앱 실행 시 새 버전이 있으면 자동 알림 → 원클릭 업데이트

## 2. Scope

### In Scope
- Apple Developer 등록 및 인증서 발급 절차
- 코드 서명 (Developer ID Application)
- Apple Notarization (공증)
- `.dmg` 설치 파일 생성
- Sparkle 프레임워크 통합 (자동 업데이트)
- GitHub Actions CI/CD 파이프라인
- 버전 넘버링 전략

### Out of Scope
- Mac App Store 배포 (Sandbox 비활성 상태로 부적합)
- Homebrew Cask 등록 (추후 인지도 확보 시 검토)
- Windows/Linux 크로스 플랫폼 (macOS 전용)
- 유료 판매 / 라이선스 관리

## 3. User Scenarios

### Scenario 1: 최초 설치
```
1. 사용자가 GitHub Releases 또는 공식 페이지에서 SBrain-1.0.0.dmg 다운로드
2. .dmg 더블클릭 → SBrain.app을 Applications 폴더로 드래그
3. 앱 실행 → GateKeeper 경고 없이 정상 실행
4. (최초 1회) macOS 권한 요청: 파일 접근, 카메라 등
```

### Scenario 2: 자동 업데이트
```
1. 사용자가 SBrain v1.0.0 사용 중
2. 개발자가 v1.1.0 태그 push → CI가 빌드·서명·공증·릴리즈
3. 사용자 앱이 시작 시 (또는 주기적으로) appcast.xml 확인
4. "새 버전 v1.1.0이 있습니다" 알림 표시
5. "업데이트" 클릭 → 자동 다운로드 + 앱 재시작
```

### Scenario 3: 긴급 패치
```
1. 보안 이슈 발견 → hotfix 브랜치에서 수정
2. v1.0.1 태그 push → CI가 즉시 빌드·배포
3. 사용자 앱이 다음 실행 시 긴급 업데이트 감지
```

## 4. Design Principles

1. **원커맨드 배포** — 태그 push 하나로 전체 파이프라인 실행
2. **서명 필수** — 모든 릴리즈 빌드는 Developer ID로 서명 + Apple 공증
3. **점진적 도입** — 수동 빌드 → 자동화 순서로 단계적 구축
4. **투명한 버전 관리** — Semantic Versioning + 릴리즈 노트 자동 생성

## 5. Structure / Flow

### 5.1 배포 방식 비교

| 방식 | 자동 업데이트 | Sandbox 필요 | 심사 | 비용 | SBrain 적합성 |
|------|:---:|:---:|:---:|:---:|:---:|
| Mac App Store | O (내장) | **필수** | 1~7일 | $99/년 + 30% | **부적합** |
| Direct + Sparkle | O (Sparkle) | 불필요 | 없음 | $99/년 | **적합** |
| Homebrew Cask | X | 불필요 | PR 리뷰 | 무료 | 보조 수단 |

**결정: Direct Distribution + Sparkle**

### 5.2 사전 준비 (1회성)

| 단계 | 작업 | 비고 |
|------|------|------|
| 1 | Apple Developer Program 등록 | $99/년, https://developer.apple.com/programs |
| 2 | Developer ID Application 인증서 발급 | Xcode > Settings > Accounts |
| 3 | Developer ID Installer 인증서 발급 | `.pkg` 서명용 (선택) |
| 4 | App-specific password 생성 | Apple ID > 앱 암호 (공증 API 인증용) |
| 5 | GitHub Repository Secrets 등록 | 인증서 `.p12`, 암호, Apple ID, Team ID |

### 5.3 빌드 → 배포 파이프라인

```
[git tag push]
    │
    ▼
[GitHub Actions: macOS runner]
    │
    ├── 1. Checkout + 인증서 설치 (Keychain import)
    ├── 2. Resolve SPM dependencies
    ├── 3. xcodebuild archive (Release)
    ├── 4. xcodebuild -exportArchive (Developer ID 서명)
    ├── 5. codesign --verify (서명 검증)
    ├── 6. xcrun notarytool submit (Apple 공증)
    ├── 7. xcrun stapler staple (공증 티켓 부착)
    ├── 8. create-dmg (설치 이미지 생성)
    ├── 9. Sparkle appcast.xml 생성/업데이트
    └── 10. GitHub Release 생성 + .dmg 업로드
```

### 5.4 Sparkle 자동 업데이트 구조

```
SBrain.app
    ├── Sparkle.framework (SPM 의존성)
    ├── Info.plist
    │   ├── SUFeedURL = "https://raw.githubusercontent.com/.../appcast.xml"
    │   └── SUPublicEDKey = "<Ed25519 공개키>"
    └── SBrainApp.swift
        └── SPUStandardUpdaterController (앱 시작 시 업데이트 확인)

GitHub Repository
    └── appcast.xml (버전, 다운로드 URL, 서명, 릴리즈 노트)
```

### 5.5 버전 넘버링

```
MARKETING_VERSION (CFBundleShortVersionString): Semantic Versioning
  - Major.Minor.Patch (예: 1.0.0, 1.1.0, 1.1.1)

CURRENT_PROJECT_VERSION (CFBundleVersion): 빌드 번호
  - 단조 증가 정수 (예: 1, 2, 3, ...)
  - CI에서 자동 증가 또는 git tag 기반 산출
```

## 6. Decision Points

### 6.1 설치 이미지 형식

| 선택지 | 장점 | 단점 |
|--------|------|------|
| `.dmg` | 표준적, 사용자 친숙 | 수동 드래그 설치 |
| `.pkg` | 자동 설치, 스크립트 가능 | 별도 Installer 인증서 필요 |
| `.zip` | 가장 간단 | 설치 경험 없음 |

**추천: `.dmg`** — macOS 앱 배포의 사실상 표준. 설치 안내 배경 이미지 포함 가능.

### 6.2 업데이트 호스팅

| 선택지 | 장점 | 단점 |
|--------|------|------|
| GitHub Releases | 무료, CI 연동 쉬움 | 대역폭 제한 (없음) |
| AWS S3 / CloudFront | CDN, 빠른 다운로드 | 비용 발생 |
| 자체 서버 | 완전 통제 | 운영 부담 |

**추천: GitHub Releases** — 현재 규모에 적합. 추후 사용자 증가 시 S3 전환 가능.

### 6.3 Sparkle 버전

| 선택지 | 설명 |
|--------|------|
| Sparkle 2 (최신) | SwiftUI 지원, XPC 기반 업데이트, Ed25519 서명 |
| Sparkle 1 | 레거시, DSA 서명 |

**추천: Sparkle 2** — SPM 지원, 보안 강화, 활발한 유지보수.

## 7. Implementation Phases

### Phase 1: 수동 빌드 배포 (즉시 가능)

Apple Developer 등록 전에도 가능한 단계:

```bash
# 1. Archive 빌드
xcodebuild archive \
  -project app/SBrain.xcodeproj \
  -scheme SBrain \
  -archivePath build/SBrain.xcarchive

# 2. .app 추출
xcodebuild -exportArchive \
  -archivePath build/SBrain.xcarchive \
  -exportPath build/ \
  -exportOptionsPlist ExportOptions.plist

# 3. .dmg 생성 (create-dmg 설치: brew install create-dmg)
create-dmg \
  --volname "SBrain" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "SBrain.app" 150 190 \
  --app-drop-link 450 190 \
  "build/SBrain.dmg" \
  "build/SBrain.app"
```

> 주의: 서명/공증 없이 배포 시 GateKeeper 경고 발생. `xattr -cr SBrain.app`으로 우회 가능하나 권장하지 않음.

### Phase 2: 코드 서명 + 공증 (Developer 등록 후)

```bash
# 1. 서명
codesign --force --deep --options runtime \
  --sign "Developer ID Application: {Team Name} ({Team ID})" \
  build/SBrain.app

# 2. 공증 제출
xcrun notarytool submit build/SBrain.dmg \
  --apple-id "your@email.com" \
  --team-id "{TEAM_ID}" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# 3. 공증 티켓 스테이플
xcrun stapler staple build/SBrain.dmg
```

### Phase 3: Sparkle 통합

```
1. project.yml에 Sparkle 2 SPM 의존성 추가
2. Ed25519 키 쌍 생성 (Sparkle의 generate_keys 도구)
3. Info.plist에 SUFeedURL, SUPublicEDKey 추가
4. SBrainApp.swift에 SPUStandardUpdaterController 초기화
5. 메뉴바에 "업데이트 확인..." 메뉴 항목 추가
```

### Phase 4: GitHub Actions CI/CD

```
1. .github/workflows/release.yml 생성
2. on: push: tags: 'v*' 트리거
3. macOS runner에서 빌드 → 서명 → 공증 → dmg → appcast → Release
4. Repository Secrets에 인증서, Apple 자격증명 등록
```

## 8. Open Issues

| 항목 | 상태 | 비고 |
|------|------|------|
| Apple Developer Program 등록 여부 | 미결정 | $99/년 비용 발생 |
| 배포 대상 범위 (본인만 vs 외부) | 미결정 | 범위에 따라 Phase 2~4 필요성 달라짐 |
| Backend(Django) 배포 방식 | 미결정 | 앱에 번들링 vs 별도 서버 vs Docker |
| 앱 아이콘 / DMG 배경 디자인 | 미착수 | 배포 시 필요 |
| Sparkle EdDSA 키 관리 방식 | 미결정 | GitHub Secrets vs 로컬 Keychain |
