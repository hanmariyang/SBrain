# Slack & Google Calendar Integration — Plan

Type: T3 – Plan / Design
Owner: gicheol
Status: In Progress
Last Updated: 2026-03-23

---

## 1. 기능 범위

### 1.1 Google Calendar 연동

| 기능 | 설명 | 우선순위 |
|------|------|---------|
| Google OAuth 로그인 | 브라우저 리디렉트 → 로컬 콜백 방식 | P0 |
| 일정 조회 | 오늘/주간/월간 뷰 | P0 |
| 일정 생성 | SBrain 내 직접 생성 | P0 |
| 일정 수정/삭제 | 기존 일정 편집 | P1 |
| 가용 시간 확인 | 빈 시간대 자동 탐색 | P2 |

### 1.2 Slack Agent 연동

| 기능 | 설명 | 우선순위 |
|------|------|---------|
| Slack OAuth 로그인 | Bot Token + User Token 발급 | P0 |
| 메시지 수집 & 분류 | @멘션·DM·채널·키워드 기반 필터링 | P0 |
| AI 분석 & 우선순위 | Claude API로 긴급도·액션 타입 판단 | P0 |
| 답변 초안 생성 | 메시지 맥락 기반 한국어 답변 초안 | P0 |
| Slack 답변 발송 | 사용자 승인 후 원본 스레드에 전송 | P0 |
| 일정 자동 추출 → Calendar 등록 | Slack 메시지에서 일정 감지 → 원클릭 Google Calendar 등록 | P1 |
| 키워드 & 채널 필터 설정 | 모니터링 대상 커스터마이즈 | P1 |
| 주기적 자동 스캔 | 30분 간격 백그라운드 스캔 | P2 |

---

## 2. 시스템 아키텍처

```
┌─────────────────────────────────────────────────┐
│                 SBrain macOS App (SwiftUI)       │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Calendar  │  │  Slack   │  │  Slack Agent  │  │
│  │   View    │  │  View    │  │  Dashboard    │  │
│  └────┬─────┘  └────┬─────┘  └──────┬────────┘  │
│       │              │               │           │
│  ┌────┴──────────────┴───────────────┴────────┐  │
│  │          APIClient (Swift)                 │  │
│  └────────────────┬───────────────────────────┘  │
└───────────────────┼──────────────────────────────┘
                    │ HTTP (localhost:8765)
┌───────────────────┼──────────────────────────────┐
│          Django Backend                          │
│                                                  │
│  ┌────────────────┴───────────────────────────┐  │
│  │              API Router                    │  │
│  └──┬──────────┬──────────────┬───────────────┘  │
│     │          │              │                   │
│  ┌──┴───┐  ┌──┴────────┐  ┌─┴──────────────┐   │
│  │Google│  │  Slack     │  │  Claude API    │   │
│  │Cal   │  │  Web API   │  │  (분석 엔진)   │   │
│  │API   │  │            │  │                │   │
│  └──────┘  └────────────┘  └────────────────┘   │
│                                                  │
│  ┌─────────────────────────────────────────────┐ │
│  │  Token Store (Keychain / encrypted .env)    │ │
│  └─────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
```

---

## 3. Slack 메시지 수집 범위

에이전트가 스캔할 "내가 관련된 메시지"의 정의:

| # | 분류 | 수집 조건 | 우선순위 |
|---|------|----------|---------|
| 1 | @멘션 | conversations.history + 본인 user_id 포함 | 매우 높음 |
| 2 | DM & 스레드 | im.list로 DM 채널 조회 후 신규 메시지 | 높음 |
| 3 | 채널 전체 | 소속 채널 conversations.history 스캔 | 중간 |
| 4 | 키워드 포함 | 설정된 키워드 매칭 (정산, 배포, EduOps 등) | 상황별 |

---

## 4. AI 분석 파이프라인

### 4.1 처리 흐름

```
트리거(수동/주기) → 수집(Slack API) → 분석(Claude API) → 제안(UI) → 실행(승인 후)
```

### 4.2 분석 출력 스키마

```json
[{
  "message_id": "string",
  "urgency": "high | medium | low",
  "action_type": "reply | calendar | both | none",
  "summary": "핵심 요청 1~2문장",
  "draft_reply": "한국어 답변 초안",
  "calendar_event": {
    "title": "string",
    "datetime": "ISO8601",
    "duration_min": 30,
    "attendees": ["string"]
  }
}]
```

### 4.3 분석 프롬프트 핵심 구조

1. **역할 정의**: 사용자의 업무 보좌 에이전트
2. **어투 가이드**: 한국어, 친근하면서 전문적
3. **분석 기준**: 마감일 언급, 블로킹 상황, 키워드 기반 긴급도 판단
4. **출력 형식**: JSON strict 스키마
5. **컨텍스트 주입**: 현재 날짜, 사용자 포지션, 주요 프로젝트 목록

---

## 5. OAuth 인증 흐름

### 5.1 Google Calendar

1. 사용자 "Google 연동" 클릭
2. 시스템 브라우저 → Google 로그인 페이지
3. 인증 후 `http://localhost:{port}/callback/google`로 리디렉트
4. Authorization code → access_token + refresh_token 교환
5. 토큰을 macOS Keychain에 저장

**Scope**: `https://www.googleapis.com/auth/calendar`

### 5.2 Slack

1. 사용자 "Slack 연동" 클릭
2. 시스템 브라우저 → Slack OAuth 페이지
3. 인증 후 `http://localhost:{port}/callback/slack`로 리디렉트
4. Bot Token + User Token 발급
5. 토큰을 macOS Keychain에 저장

**Scopes**: `channels:history`, `channels:read`, `chat:write`, `im:history`, `im:read`, `users:read`

---

## 6. UI 설계

### 6.1 ViewMode 추가

```swift
enum ViewMode {
    case brain     // 기존: 3D Brain Map
    case list      // 기존: 파일 리스트
    case database  // 기존: DB 브라우저
    case calendar  // 신규: Google Calendar
    case slack     // 신규: Slack Agent Dashboard
}
```

### 6.2 SidebarIconBar 아이콘

| 아이콘 | ViewMode | SF Symbol |
|--------|----------|-----------|
| 뇌 | .brain | `brain.head.profile` |
| 리스트 | .list | `list.bullet` |
| DB | .database | `cylinder.split.1x2` |
| 캘린더 | .calendar | `calendar` |
| 슬랙 | .slack | `message.badge` |

### 6.3 Calendar View 구성

- **ExplorerPanel**: 월간 미니 캘린더 + 당일 일정 리스트
- **메인 영역**: 주간/월간 상세 뷰 + 일정 생성/편집 패널

### 6.4 Slack Agent Dashboard 구성

- **ExplorerPanel**: 채널 리스트 + 필터 설정
- **메인 영역**: 메시지 카드 리스트 (긴급도 색상 구분)
  - 각 카드: 요약 + 답변 초안 + 액션 버튼 (발송/일정등록/무시)

---

## 7. Django 백엔드 API

### 7.1 Google Calendar

```
POST /api/auth/google/          → OAuth 시작 (redirect URL 반환)
POST /api/auth/google/callback/ → 토큰 교환
GET  /api/calendar/events/      ?start=&end= → 일정 조회
POST /api/calendar/events/      → 일정 생성
PUT  /api/calendar/events/{id}/ → 일정 수정
DELETE /api/calendar/events/{id}/ → 일정 삭제
```

### 7.2 Slack Agent

```
POST /api/auth/slack/           → OAuth 시작
POST /api/auth/slack/callback/  → 토큰 교환
POST /api/slack/scan/           → 메시지 스캔 실행
GET  /api/slack/messages/       → 분석된 메시지 목록
POST /api/slack/reply/          → 승인 후 답변 발송
POST /api/slack/calendar/       → 메시지 → 일정 등록 (Calendar API 연계)
GET  /api/slack/settings/       → 필터 설정 조회
PUT  /api/slack/settings/       → 필터 설정 변경
```

---

## 8. 보안 원칙

- 모든 "실행" 액션(답변 발송, 일정 등록)은 **사용자 승인 후**에만 처리
- Slack 메시지 내용은 분석 후 **로컬에 저장하지 않음** (메시지 ID만 기록)
- OAuth 토큰은 **macOS Keychain**에 암호화 저장
- API 키(Google Client Secret, Slack Client Secret)는 `.env`에서 관리, 코드에 미포함

---

## 9. 구현 로드맵

| Phase | 이름 | 주요 작업 | 산출물 |
|-------|------|----------|--------|
| **Phase 0** | 인증 & 골격 | Google/Slack OAuth + ViewMode 추가 + 빈 뷰 | 연동 로그인 동작 |
| **Phase 1** | Calendar 기본 | 일정 CRUD + 주간/월간 뷰 | 캘린더 기능 완성 |
| **Phase 2** | Slack 수집 & 분석 | 메시지 수집 + Claude 분석 + 대시보드 UI | Slack Agent 기본 동작 |
| **Phase 3** | 액션 실행 | 답변 발송 + 일정 연계 등록 | 원클릭 실행 |
| **Phase 4** | 자동화 & 고도화 | 주기적 스캔 + 키워드 필터 + 학습 | 완전 자동화 |

---

## 10. 사전 준비 사항

- [ ] Google Cloud Console에서 OAuth 2.0 Client ID 생성 (Desktop App 타입)
- [ ] Slack App 생성 (api.slack.com) + OAuth scopes 설정 + Bot User 추가
- [ ] Anthropic API Key 확인 (기존 SBrain `.env`의 `ANTHROPIC_API_KEY` 활용)
- [ ] 모니터링 채널 목록 및 키워드 초기값 정의
