# Slack & Google Calendar Integration — Execution Log

Type: T6 – Execution Log
Owner: gicheol
Status: Done
Last Updated: 2026-03-24

---

## 이슈 & 트러블슈팅

### 1. Calendar/Slack 패널-메인 뷰 중복 (3회 반복)
- **증상**: ExplorerPanel과 메인 영역이 동일한 연결/인증 UI를 각각 표시
- **근본 원인**: DB 브라우저와 동일한 패턴 — 두 뷰가 독립적으로 상태를 렌더링
- **해결**: 인증/연결 UI는 ExplorerPanel 전담, 메인은 콘텐츠만 표시. 미연결 시 "사이드바에서 연결하세요" 안내
- **교훈**: 새 ViewMode 추가 시 반드시 ExplorerPanel vs 메인 역할 분리 확인

### 2. Google OAuth TemplateDoesNotExist (3회 반복)
- **증상**: `/api/calendar/auth/callback/`에서 `rest_framework/api.html` 템플릿 에러
- **시도 1**: `@api_view` 제거 → 실패 (Python __pycache__ 캐시 문제)
- **시도 2**: 콜백을 `config/urls.py`에 직접 등록 → 실패 (캐시 지속)
- **최종 해결**: 완전히 새 파일 `oauth_callback.py` 생성, `@csrf_exempt` + `HttpResponse` 사용
- **교훈**: DRF 뷰를 순수 Django 뷰로 변경 시 `__pycache__` 삭제 필수

### 3. Google OAuth PKCE code_verifier 불일치
- **증상**: "토큰 교환에 실패했습니다"
- **원인**: `get_auth_url()`과 `exchange_code()`가 각각 별도 `Flow` 인스턴스 생성 → PKCE `code_verifier` 불일치. Gunicorn 멀티 워커 환경에서 state 공유 불가
- **해결**: `google-auth-oauthlib` Flow 대신 직접 `requests.post("https://oauth2.googleapis.com/token")` 호출
- **교훈**: 서버 사이드 OAuth에서 PKCE는 stateless 환경과 충돌

### 4. Google OAuth Client 타입 오류
- **증상**: redirect URI 추가 UI가 안 나옴
- **원인**: "데스크톱 앱" 타입 OAuth Client에는 redirect URI 설정 불가
- **해결**: "웹 애플리케이션" 타입으로 새로 생성, redirect URI 등록
- **교훈**: 서버 콜백이 필요한 OAuth는 반드시 웹 애플리케이션 타입

### 5. Slack OAuth HTTPS 필수
- **증상**: Slack redirect URL에 localhost 등록 불가 ("Please use a complete URL beginning with https")
- **해결**: Django 백엔드를 Railway에 HTTPS 서버로 배포
- **파급**: 앱의 API baseURL도 `localhost:8765` → Railway 서버로 변경

### 6. API 응답 형식 불일치 (3건)
- **Calendar Auth**: `POST` → 백엔드 `GET`만 허용 (405)
- **Slack Channels**: `[SlackChannel]` 직접 디코딩 → `{"channels":[...]}` 래퍼
- **Slack Status**: Swift 모델에 `workspace` 기대 → 백엔드는 `pending_count` 반환
- **Calendar Events**: `[CalendarEvent]` → `{"events":[], "count":N}` 래퍼
- **CalendarEvent**: `is_all_day`, `location` 필드 백엔드 미반환
- **해결**: APIClient 래퍼 struct 추가, 모델 필드 수정

### 7. Slack Socket Mode 이벤트 미수신
- **증상**: `connected: true`이지만 이벤트가 핸들러에 도달하지 않음
- **원인**: `slack_bolt`의 `App(token=bot_token)` 사용 시 내부적으로 `installation_store`/`authorize` 모드로 전환되어 토큰 무시
- **해결**: `slack_bolt` 대신 `slack_sdk`의 `SocketModeClient` 직접 사용
- **추가 이슈**: daemon 스레드에서 `signal.pause()` 미동작 → `threading.Event().wait()` 사용

### 8. Slack 메시지 0개 (필터 로직)
- **증상**: 메시지가 채널에 있지만 스캔 결과 0개
- **원인 1**: `user_id` 미설정 시 `else` 분기 누락으로 모든 메시지 무시
- **원인 2**: 본인이 보낸 메시지 전부 제외 (테스트 시 자기 자신만 존재)
- **해결**: `user_id` 없을 때 키워드 필터만 적용, 키워드 매칭은 본인 메시지도 허용

### 9. Claude API 크레딧 부족
- **증상**: 스캔 완료되지만 분석 결과 0개
- **원인**: Anthropic API 잔액 부족 (`credit balance is too low`)
- **해결**: AI 분석을 선택적으로 변경. 기본: 수집만 모드, `?ai=true`: AI 분석 모드

### 10. 인메모리 설정 초기화
- **증상**: Railway 재배포 시 keywords, user_id 전부 초기화
- **원인**: 설정이 Python 인메모리 dict에만 저장
- **현재 상태**: 미해결 (재배포 시 재설정 필요). 향후 DB/파일 영속화 필요

### 11. Sparkle appcast.xml 버전 하드코딩
- **증상**: appcast에 `version: 1.0` 기록, 업데이트 감지 불가
- **원인**: XcodeGen이 생성한 Info.plist에 `CFBundleShortVersionString: 1.0` 하드코딩
- **해결**: `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)` 변수 참조로 변경

### 12. Sparkle appcast.xml 접근 불가 (private repo)
- **증상**: "An error occurred in retrieving update information"
- **원인**: GitHub 리포가 private → `raw.githubusercontent.com` 404 반환
- **해결**: Railway 서버에서 appcast.xml 프록시 엔드포인트 추가, SUFeedURL 변경

---

## 릴리즈 히스토리

| 버전 | 주요 내용 | 날짜 |
|------|----------|------|
| v0.7.0 | Slack/Calendar 연동 초기 릴리즈 | 2026-03-23 |
| v0.7.1 | Info.plist 버전 변수 참조 수정 | 2026-03-23 |
| v0.7.2 | SUFeedURL Railway 프록시 적용 | 2026-03-24 |
