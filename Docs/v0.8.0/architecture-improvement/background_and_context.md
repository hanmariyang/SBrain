# Background: SBrain v0.8.0 Architecture Improvement

Type: T2 – Background & Context
Owner: gicheol
Status: Draft
Last Updated: 2026-03-24

---

## 1. Background Summary

SBrain v0.7.x는 Slack 연동, Google Calendar 연동, 3D Brain Map, 통합 터미널 등 핵심 기능을 갖춘 macOS 데스크탑 앱이다.
그러나 앱을 재시작할 때마다 **외부 서비스 인증이 초기화**되고, **프로젝트 폴더의 파일 변경 사항이 실시간 반영되지 않는** 구조적 문제가 존재한다.

현재 아키텍처는 "기능 추가 중심"으로 빠르게 성장해 왔으나, **상태 영속화(State Persistence)**와 **이벤트 기반 반응성(Event-Driven Reactivity)** 측면에서 설계 부채가 누적된 상태이다.

---

## 2. Problem Definition

### 대상 사용자
- SBrain을 일상적으로 사용하는 개인 사용자 (개발자, 지식 관리자)

### 문제 1: 앱 재시작 시 외부 서비스 재인증 필요

| 서비스 | 토큰 저장 방식 | 재시작 시 상태 |
|--------|---------------|---------------|
| Google Calendar | `backend/.google_tokens.json` (파일) | 토큰 파일 자체는 유지되나, 백엔드 초기화 타이밍에 따라 미인증으로 판단 |
| Slack | `slack_service._filter_settings["user_id"]` (인메모리) | **완전 소실** → 매번 OAuth 재인증 필수 |

**SwiftUI 앱 측 문제**:
- 인증 상태를 자체 저장하지 않음 (백엔드 폴링 의존)
- `ContentView.task`에서 2초 딜레이 후 프로젝트 복원 → 백엔드 미준비 시 인증 체크 실패
- 백엔드 `isRunning` 상태와 인증 체크 타이밍이 동기화되지 않음

**백엔드 측 문제**:
- Slack `user_id`가 모듈 레벨 딕셔너리(`_filter_settings`)에만 저장
- `IntegrationsConfig.ready()`에서 Socket Mode 스레드 시작 시 이전 유저 컨텍스트 없음
- Slack 메시지 목록(`_messages`), 처리 ID(`_processed_ids`) 모두 인메모리 → 재시작 시 전량 소실

### 문제 2: 프로젝트 문서/폴더 변경 실시간 미반영

| 구성요소 | 현재 동작 | 한계 |
|----------|----------|------|
| `FolderScanner.scan(at:)` | 1회성 재귀 디렉토리 탐색 | 이후 변경 감지 불가 |
| `NoteStore.restoreProjects()` | 앱 시작 시 1회 실행 | 실행 중 파일 추가/삭제 미반영 |
| `NoteStore.refreshBaseFolder()` | 수동 호출 전용 | 외부 편집기 변경 시 반영 안 됨 |
| FSEvents / FileWatcher | **미구현** | macOS FSEvents API 미사용 |
| Backend ingest | 프로젝트 추가 시 1회 실행 | 파일 변경 후 재인덱싱 트리거 없음 |

---

## 3. Root Cause Hypothesis

### 가설 1: 상태 영속화 레이어 부재
- 백엔드가 "요청-응답" 위주의 stateless 설계
- 인메모리 상태(`_messages`, `_filter_settings`, `_processed_ids`)가 프로세스 수명에 종속
- SwiftUI 앱도 인증 상태를 캐시하지 않아 백엔드 의존도 100%

### 가설 2: 이벤트 기반 아키텍처 미적용
- 파일 시스템 변경을 감지하는 FSEvents/DispatchSource가 전혀 없음
- 모든 데이터 갱신이 "사용자 액션 → API 호출 → 수동 리프레시" 패턴
- 백엔드와 프론트엔드 간 실시간 통신 채널(WebSocket, SSE 등) 부재

### 가설 3: 앱 라이프사이클과 백엔드 라이프사이클 미동기화
- `BackendManager.start()` 완료 시점과 `NoteStore.restoreProjects()` / 인증 체크 시점 간 경쟁 조건(race condition)
- 2초 하드코딩 딜레이로 우회 중이나, 백엔드 시작이 느릴 경우 실패

---

## 4. Risk If Not Addressed

### 사용자 경험 리스크
- 매 실행 시 Google OAuth + Slack OAuth 반복 → **앱 시작 비용 증가** → 사용 빈도 감소
- 파일 변경이 즉시 보이지 않음 → **"데이터가 사라졌다"는 착각** → 신뢰도 하락

### 데이터 정합성 리스크
- Slack 메시지 인메모리 소실 → 중요 메시지 분석 결과 유실
- 파일 변경 미감지 → Brain Graph가 실제 프로젝트 상태와 불일치
- 인덱스(Neuron/Synapse)와 실제 파일 시스템 간 drift 발생

### 확장성 리스크
- 향후 기능(실시간 협업, 자동 요약 등) 추가 시 이벤트 기반 구조 필수
- 현재 구조에서는 매번 폴링 기반 워크어라운드 누적

---

## 5. Target Outcome

| 항목 | 목표 상태 |
|------|----------|
| OAuth 인증 | 앱 재시작 후 **자동 복원** (재인증 불필요) |
| Slack 컨텍스트 | `user_id`, 메시지 목록이 **영구 저장** → 재시작 후 즉시 사용 가능 |
| 파일 변경 감지 | FSEvents 기반 **실시간 감지** → 사이드바 트리 자동 갱신 |
| 인덱스 동기화 | 변경된 파일만 **부분 재인덱싱** → Brain Graph 자동 반영 |
| 앱 시작 흐름 | 백엔드 ready 확인 후 **순차적 초기화** (race condition 제거) |
