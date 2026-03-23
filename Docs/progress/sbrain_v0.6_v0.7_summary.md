# SBrain v0.6.0 ~ v0.7.2 Progress Summary

Type: T1 – Overview / Summary
Owner: gicheol
Status: Done
Last Updated: 2026-03-24

---

## 개요

v0.6.0부터 v0.7.2까지의 진행 요약. 다크모드 → 라이트모드 UI 전환, 릴리즈 파이프라인 구축, Slack/Google Calendar 외부 서비스 연동까지 완료.

---

## 버전별 변경 요약

### v0.6.0 — UI/UX 리디자인 (라이트모드)
- 다크모드 → 라이트모드 전면 전환 (navy #1B2A4A + gold #C4973B 브랜드 컬러)
- SB 디자인 시스템: DesignTokens.swift (Colors, Font, Space, Radius, Layout)
- 2-tier 사이드바 레이아웃 (SidebarIconBar 48px + ExplorerPanel 240px)
- 전체 뷰 컬러 리스타일링 (11개 파일)
- BrainMap 라이트 테마 + 노드 선택 → 디테일 뷰 연동
- 마크다운 CSS 라이트모드 재작성 (WKWebView)
- SwiftTerm 터미널 라이트 컬러 + 뷰 재사용 크래시 수정
- 앱 아이콘 추가 (logo01 기반)

### v0.6.1 — 릴리즈 파이프라인 수정
- GitHub Actions CI 러너 macos-14 → macos-15 (Xcode 16 호환)
- permissions: contents: write 추가
- xcodebuild -exportArchive 도입 (코드사인 정상화)
- Notarize 실패 시 상세 로그 출력
- appcast 중복 버전 에러 수정
- Sparkle 앱 시작 시 자동 업데이트 확인

### v0.6.2 — 핫픽스
- DB 테이블 리스트 중복 표시 제거
- Sparkle SUFeedURL Info.plist 누락 수정
- 앱 아이콘 logo03으로 변경 (cream 배경 + 크롭)

### v0.7.0 — Slack & Google Calendar 연동
- **Slack 연동**
  - Socket Mode 실시간 메시지 수신 (slack_sdk SocketModeClient)
  - Slack OAuth 사용자 인증 (HTTPS 서버 필수)
  - 메시지 필터링: 멘션, DM, 키워드
  - AI 분석 선택적 사용 (Claude API, 크레딧 없이도 동작)
  - 답변 발송 기능
  - 5초 자동 폴링
- **Google Calendar 연동**
  - OAuth 2.0 인증 (웹 애플리케이션 타입)
  - 일정 CRUD (본인 소유/참여 캘린더만)
  - 월간 미니 캘린더 (ExplorerPanel) + 일정 상세 (메인)
- **인프라**
  - Railway 서버 배포 (gunicorn + CORS + HTTPS)
  - API baseURL: localhost → `https://sbrain-production-0f09.up.railway.app`
  - 설정 뷰 (백엔드/Slack/Calendar 상태 확인)

### v0.7.1 — 핫픽스
- Info.plist 버전을 빌드 설정 변수 참조로 변경

### v0.7.2 — 핫픽스
- SUFeedURL을 Railway 서버 프록시로 변경 (private repo appcast.xml 접근)

---

## 기술 스택 변경

| 항목 | v0.5.0 이전 | v0.7.2 현재 |
|------|------------|------------|
| 테마 | 다크모드 | 라이트모드 (navy/gold) |
| 사이드바 | 단일 패널 | 2-tier (IconBar + ExplorerPanel) |
| 백엔드 | 로컬 subprocess | Railway 서버 (HTTPS) |
| 외부 연동 | 없음 | Slack + Google Calendar |
| 업데이트 | 수동 | Sparkle 자동 (Railway 프록시) |
| CI/CD | 없음 | GitHub Actions (빌드→서명→공증→DMG→Release) |

---

## 알려진 이슈 / 향후 과제

1. **인메모리 설정 초기화**: Railway 재배포 시 Slack 사용자/키워드 설정 리셋 → DB 영속화 필요
2. **Slack → WebSocket 직접 연결**: 현재 5초 폴링, 추후 Django Channels로 실시간 전환 가능
3. **AI 분석 크레딧**: Anthropic API 크레딧 충전 필요
4. **멀티 유저 지원**: 현재 단일 사용자 가정, 추후 인증 시스템 필요
