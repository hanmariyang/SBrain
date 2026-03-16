# Plan: Integrated Terminal — 멀티 탭 터미널 에뮬레이터

Type: T3 – Plan / Design
Owner: gicheol
Status: Done
Last Updated: 2026-03-17

---

## 1. Goal

- SBrain 내에서 완전한 터미널 에뮬레이터를 실행한다
- 여러 터미널 세션을 동시에 생성/전환/종료할 수 있다
- 선택된 프로젝트 폴더를 working directory로 자동 설정한다

성공 기준:
1. zsh/bash 셸이 정상 실행되고 ANSI 컬러가 표시된다
2. 최소 4개 이상의 터미널을 동시에 실행할 수 있다
3. 터미널 탭 간 전환이 즉각적이다

## 2. Scope

### In Scope
- SwiftTerm 라이브러리를 이용한 터미널 에뮬레이터
- 멀티 탭: 생성(+), 전환(클릭), 종료(x)
- ViewMode에 .terminal 추가
- 프로젝트 폴더를 초기 working directory로 설정
- 다크 테마 커스텀 (SBrain 색상 일관성)

### Out of Scope
- 분할 터미널 (split pane)
- 터미널 세션 직렬화/복원
- SSH 프로필 관리

## 3. User Scenarios

### Scenario 1: 터미널 열기
1. 상단 모드 바에서 터미널 아이콘 클릭
2. 기본 셸(zsh)이 프로젝트 폴더에서 시작
3. 명령어 입력/실행

### Scenario 2: 여러 터미널 탭
1. 터미널 탭 바에서 "+" 클릭
2. 새 터미널 탭 생성 (자동 번호 부여: Terminal 1, 2, 3...)
3. 탭 클릭으로 전환, x 버튼으로 종료

## 4. Design Principles

1. SwiftTerm NSView를 NSViewRepresentable로 래핑
2. TerminalManager가 여러 세션의 lifecycle 관리
3. 각 세션은 독립적인 Process + PTY
4. 터미널 뷰 전환 시 프로세스 유지 (백그라운드 실행)

## 5. Structure

### 5.1 새 파일

| 파일 | 역할 |
|------|------|
| `Services/TerminalManager.swift` | 멀티 세션 관리 (생성/전환/종료) |
| `Views/TerminalView.swift` | SwiftTerm 래핑 + 탭 바 UI |

### 5.2 수정 파일

| 파일 | 변경 |
|------|------|
| `project.yml` | SwiftTerm SPM 의존성 추가 |
| `Views/ContentView.swift` | ViewMode에 .terminal 추가 |
| `SBrainApp.swift` | TerminalManager environmentObject 등록 |

## 6. Decision Points

| 선택지 | 추천 | 근거 |
|--------|------|------|
| 터미널 라이브러리 | SwiftTerm | 네이티브 Swift, 완전한 VT100 에뮬레이션 |
| UI 배치 | ViewMode 탭 | 기존 UI 패턴 일관성 유지 |
| 초기 디렉토리 | 선택된 프로젝트 폴더 | 사용자 컨텍스트 유지 |
