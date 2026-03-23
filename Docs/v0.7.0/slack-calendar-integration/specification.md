# Slack & Google Calendar Integration — Specification

Type: T4 – Specification
Owner: gicheol
Status: Done
Last Updated: 2026-03-24

---

## 1. 서버 배포

| 항목 | 값 |
|------|-----|
| 플랫폼 | Railway |
| URL | `https://sbrain-production-0f09.up.railway.app` |
| 런타임 | Python 3.11 + gunicorn (1 worker, 4 threads) |
| 컨테이너 | Dockerfile 기반 |
| 자동 배포 | `railway up` CLI |

---

## 2. Backend API 엔드포인트

### 2.1 Slack

```
GET  /api/slack/status/         → 연결 상태 + 대기 메시지 수
POST /api/slack/scan/           → 메시지 수집 + 분석 (?ai=true로 AI 분석)
GET  /api/slack/messages/       → 최근 분석 결과 캐시
POST /api/slack/reply/          → 승인된 답변 발송
GET  /api/slack/channels/       → 채널 목록 (봇 참여 중)
GET  /api/slack/settings/       → 필터 설정 조회
PUT  /api/slack/settings/       → 필터 설정 변경 (channels, keywords)
GET  /api/slack/auth/           → Slack OAuth URL 생성
GET  /api/slack/auth/callback/  → Slack OAuth 콜백 (브라우저 → HTML)
GET  /api/slack/user/           → 현재 인증된 사용자 정보
GET  /api/slack/debug/          → 디버그: 이벤트 로그, 수집/스킵 상태
```

### 2.2 Google Calendar

```
GET  /api/calendar/auth/           → Google OAuth URL 생성
GET  /api/calendar/auth/callback/  → Google OAuth 콜백 (브라우저 → HTML)
GET  /api/calendar/status/         → 인증 상태 확인
GET  /api/calendar/events/         → 일정 목록 (?start=&end= ISO8601)
POST /api/calendar/events/         → 일정 생성
PUT  /api/calendar/events/{id}/    → 일정 수정
DELETE /api/calendar/events/{id}/  → 일정 삭제
```

### 2.3 Sparkle 업데이트

```
GET  /appcast.xml                  → GitHub private repo appcast.xml 프록시
```

---

## 3. 응답 스키마

### 3.1 Slack 스캔 결과

```json
{
  "detail": "Scan completed",
  "count": 3,
  "results": [
    {
      "id": "uuid",
      "message_id": "uuid",
      "channel": "C0AMTTYP85V",
      "channel_name": "sbrain_test",
      "user": "U04P8G95ZQS",
      "user_name": "양기철",
      "text": "메시지 내용",
      "timestamp": "1774275547.934169",
      "thread_ts": "",
      "urgency": "low",
      "action_type": "none",
      "summary": "",
      "draft_reply": "",
      "calendar_event": null
    }
  ]
}
```

### 3.2 Calendar 이벤트

```json
{
  "events": [
    {
      "id": "event_id",
      "title": "회의",
      "start": "2026-03-24T10:00:00+09:00",
      "end": "2026-03-24T11:00:00+09:00",
      "description": "",
      "location": null,
      "attendees": ["user@example.com"],
      "html_link": "https://...",
      "status": "confirmed",
      "calendar_name": "기본 캘린더"
    }
  ],
  "count": 1
}
```

---

## 4. Slack 메시지 수신 아키텍처

```
                     ┌─────────────────────┐
 Slack Workspace ──→ │ Socket Mode (WSS)   │──→ _store_message()
                     │ slack_sdk Client     │    (인메모리 저장)
                     └─────────────────────┘
                              │
                     ┌────────┴────────┐
                     │  필터링 로직     │
                     │  ① 멘션 확인    │
                     │  ② DM 확인     │
                     │  ③ 키워드 매칭  │
                     └────────┬────────┘
                              │
                     ┌────────┴────────┐
                     │ Web API 보완    │  ← conversations.history
                     │ (스캔 시 실행)   │    (Socket Mode 보완용)
                     └────────┬────────┘
                              │
                     ┌────────┴────────┐
                     │ 5초 폴링        │  ← SlackStore (SwiftUI)
                     │ /api/slack/scan │
                     └─────────────────┘
```

---

## 5. OAuth 인증 흐름

### 5.1 Google Calendar
1. 앱 → `GET /api/calendar/auth/` → OAuth URL 반환
2. 브라우저 → Google 로그인 → 승인
3. 리디렉트 → `GET /api/calendar/auth/callback/?code=...`
4. 서버 → `https://oauth2.googleapis.com/token`으로 코드 교환
5. 토큰 → `backend/.google_tokens.json`에 저장
6. 앱 → 2초 폴링 → `authenticated: true` 감지

### 5.2 Slack
1. 앱 → `GET /api/slack/auth/` → OAuth URL 반환
2. 브라우저 → Slack 로그인 → 승인
3. 리디렉트 → `GET /api/slack/auth/callback/?code=...`
4. 서버 → `https://slack.com/api/oauth.v2.access`로 코드 교환
5. `authed_user.id` → `set_current_user()` → 인메모리 저장
6. 앱 → 2초 폴링 → `authenticated: true` 감지

---

## 6. 환경 변수

| 변수 | 용도 |
|------|------|
| `SLACK_APP_TOKEN` | Socket Mode WebSocket 연결 (xapp-...) |
| `SLACK_BOT_TOKEN` | Slack API 호출 (xoxb-...) |
| `SLACK_SIGNING_SECRET` | 요청 검증 |
| `SLACK_CLIENT_ID` | Slack OAuth (사용자 인증) |
| `SLACK_CLIENT_SECRET` | Slack OAuth |
| `GOOGLE_CLIENT_ID` | Google OAuth (웹 애플리케이션 타입) |
| `GOOGLE_CLIENT_SECRET` | Google OAuth |
| `GITHUB_TOKEN` | appcast.xml 프록시 (private repo 접근) |
| `ANTHROPIC_API_KEY` | Claude API (AI 분석, 선택적) |
| `RAILWAY_PUBLIC_DOMAIN` | 서버 공개 도메인 (동적 redirect URI) |

---

## 7. 프론트엔드 구조

### 7.1 새로 추가된 ViewMode
- `.calendar` — Google Calendar 일정 뷰
- `.slack` — Slack Agent 대시보드

### 7.2 새 파일 목록

| 파일 | 역할 |
|------|------|
| `SlackModels.swift` | SlackMessage, SlackChannel, CalendarEventSuggestion |
| `CalendarModels.swift` | CalendarEvent |
| `SlackStore.swift` | Slack 상태 관리 + 5초 폴링 |
| `CalendarStore.swift` | Calendar 상태 관리 + OAuth |
| `SlackAgentView.swift` | 메시지 카드 대시보드 (메인) |
| `CalendarView.swift` | 선택된 날짜 일정 상세 (메인) |
| `SlackExplorerView.swift` | 채널 리스트 + 연결 상태 (사이드바) |
| `CalendarExplorerView.swift` | 미니 캘린더 + 일정 리스트 (사이드바) |
| `SettingsView.swift` | 앱 설정 (백엔드/Slack/Calendar 상태) |
