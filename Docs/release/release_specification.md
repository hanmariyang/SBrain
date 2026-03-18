# Specification: Release Pipeline Configuration

Type: T4 – Specification
Owner: gicheol
Status: Draft
Last Updated: 2026-03-18

---

## 1. Purpose

SBrain macOS 앱의 빌드, 서명, 공증, 배포, 자동 업데이트에 필요한 구체적 설정값과 파일 명세를 정의한다.

## 2. 프로젝트 빌드 설정

### 2.1 현재 설정 (project.yml)

| 키 | 현재 값 | 배포 시 변경 |
|----|---------|-------------|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.hanmari.sbrain` | 유지 |
| `MARKETING_VERSION` | `0.1.0` | 릴리즈 버전으로 업데이트 |
| `CURRENT_PROJECT_VERSION` | `1` | CI에서 자동 증가 |
| `SWIFT_VERSION` | `5.9` | 유지 |
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` | 유지 |
| `CODE_SIGN_IDENTITY` | (미설정) | `Developer ID Application` |
| `CODE_SIGN_STYLE` | (미설정) | `Manual` |
| `DEVELOPMENT_TEAM` | (미설정) | Apple Team ID |

### 2.2 배포 시 추가할 설정

```yaml
# project.yml targets.SBrain.settings.base에 추가
CODE_SIGN_IDENTITY: "Developer ID Application"
CODE_SIGN_STYLE: Manual
DEVELOPMENT_TEAM: "${TEAM_ID}"
ENABLE_HARDENED_RUNTIME: YES
```

> Hardened Runtime은 공증(Notarization) 필수 조건

### 2.3 Entitlements 추가 항목

현재 `SBrain.entitlements`:
```xml
com.apple.security.app-sandbox: false
com.apple.security.network.client: true
```

Hardened Runtime 활성화 시 추가 필요:
```xml
com.apple.security.cs.allow-unsigned-executable-memory: true  <!-- SwiftTerm PTY -->
com.apple.security.device.camera: true                        <!-- 손 제스처 -->
com.apple.security.automation.apple-events: true              <!-- 선택: 외부 앱 연동 -->
```

## 3. SPM 의존성 (Sparkle 추가)

```yaml
# project.yml packages에 추가
packages:
  SwiftTerm:
    url: https://github.com/migueldeicaza/SwiftTerm
    from: "1.2.0"
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"

# targets.SBrain.dependencies에 추가
dependencies:
  - package: SwiftTerm
  - package: Sparkle
    product: Sparkle
```

## 4. Info.plist 추가 키

```xml
<!-- Sparkle 자동 업데이트 -->
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/hanmariyang/SBrain/main/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>{Ed25519 공개키 — generate_keys로 생성}</string>

<!-- 선택: 자동 업데이트 확인 주기 (초) -->
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>  <!-- 24시간 -->
```

project.yml에서 설정:
```yaml
settings:
  base:
    INFOPLIST_KEY_SUFeedURL: "https://raw.githubusercontent.com/hanmariyang/SBrain/main/appcast.xml"
```

## 5. ExportOptions.plist

Archive → Export 시 필요한 설정 파일:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>{TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
```

## 6. GitHub Actions Workflow

### 6.1 파일 경로
```
.github/workflows/release.yml
```

### 6.2 트리거
```yaml
on:
  push:
    tags:
      - 'v*'
```

### 6.3 필요한 Repository Secrets

| Secret 이름 | 설명 | 획득 방법 |
|-------------|------|----------|
| `APPLE_CERTIFICATE_P12` | Developer ID 인증서 (Base64) | Keychain에서 .p12 export → `base64 -i cert.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | .p12 파일 비밀번호 | export 시 설정한 값 |
| `APPLE_ID` | Apple Developer 이메일 | developer.apple.com 계정 |
| `APPLE_TEAM_ID` | Apple Developer Team ID | developer.apple.com > Membership |
| `APPLE_APP_PASSWORD` | 앱 전용 비밀번호 | appleid.apple.com > 앱 암호 |
| `SPARKLE_PRIVATE_KEY` | Ed25519 서명 비밀키 | `./bin/generate_keys` (Sparkle 도구) |

### 6.4 Workflow 핵심 단계

```yaml
jobs:
  release:
    runs-on: macos-14
    steps:
      # 1. 체크아웃
      - uses: actions/checkout@v4

      # 2. 인증서 설치
      - name: Install certificate
        env:
          P12_BASE64: ${{ secrets.APPLE_CERTIFICATE_P12 }}
          P12_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: |
          echo "$P12_BASE64" | base64 --decode > cert.p12
          security create-keychain -p "" build.keychain
          security import cert.p12 -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain
          security default-keychain -s build.keychain

      # 3. 버전 추출
      - name: Get version from tag
        run: echo "VERSION=${GITHUB_REF#refs/tags/v}" >> $GITHUB_ENV

      # 4. SPM 의존성
      - name: Resolve dependencies
        run: xcodebuild -resolvePackageDependencies -project app/SBrain.xcodeproj -scheme SBrain

      # 5. Archive
      - name: Archive
        run: |
          xcodebuild archive \
            -project app/SBrain.xcodeproj \
            -scheme SBrain \
            -configuration Release \
            -archivePath build/SBrain.xcarchive \
            MARKETING_VERSION=${{ env.VERSION }}

      # 6. Export (서명됨)
      - name: Export
        run: |
          xcodebuild -exportArchive \
            -archivePath build/SBrain.xcarchive \
            -exportPath build/ \
            -exportOptionsPlist app/ExportOptions.plist

      # 7. 공증
      - name: Notarize
        run: |
          ditto -c -k --keepParent "build/SBrain.app" build/SBrain.zip
          xcrun notarytool submit build/SBrain.zip \
            --apple-id "${{ secrets.APPLE_ID }}" \
            --team-id "${{ secrets.APPLE_TEAM_ID }}" \
            --password "${{ secrets.APPLE_APP_PASSWORD }}" \
            --wait
          xcrun stapler staple "build/SBrain.app"

      # 8. DMG 생성
      - name: Create DMG
        run: |
          brew install create-dmg
          create-dmg \
            --volname "SBrain" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "SBrain.app" 150 190 \
            --app-drop-link 450 190 \
            "build/SBrain-${{ env.VERSION }}.dmg" \
            "build/SBrain.app"

      # 9. Sparkle appcast 업데이트
      - name: Update appcast
        run: |
          ./bin/generate_appcast \
            --ed-key-file <(echo "${{ secrets.SPARKLE_PRIVATE_KEY }}") \
            build/

      # 10. GitHub Release
      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/SBrain-${{ env.VERSION }}.dmg
          generate_release_notes: true
```

## 7. appcast.xml 구조

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SBrain Updates</title>
    <language>ko</language>
    <item>
      <title>Version 1.0.0</title>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>Mon, 18 Mar 2026 00:00:00 +0900</pubDate>
      <enclosure
        url="https://github.com/hanmariyang/SBrain/releases/download/v1.0.0/SBrain-1.0.0.dmg"
        length="12345678"
        type="application/octet-stream"
        sparkle:edSignature="{Ed25519 서명}" />
      <description><![CDATA[
        <h2>새로운 기능</h2>
        <ul>
          <li>3D Brain Map</li>
          <li>멀티 프로젝트 지원</li>
          <li>통합 터미널</li>
        </ul>
      ]]></description>
    </item>
  </channel>
</rss>
```

> `generate_appcast` 도구가 .dmg 파일을 분석하여 자동 생성하므로 수동 작성 불필요.

## 8. 디렉토리 구조 (배포 관련 파일)

```
SBrain/
├── .github/
│   └── workflows/
│       └── release.yml              ← CI/CD 파이프라인
├── app/
│   ├── ExportOptions.plist          ← Archive export 설정
│   ├── project.yml                  ← Sparkle 의존성 추가
│   └── SBrain/
│       ├── SBrain.entitlements      ← Hardened Runtime 권한
│       └── SBrainApp.swift          ← SPUStandardUpdaterController
├── appcast.xml                      ← Sparkle 업데이트 피드 (자동 생성)
└── Docs/
    └── release/                     ← 배포 관련 문서
```
