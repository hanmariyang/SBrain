# Background: Integrated Terminal — VS Code 스타일 내장 터미널

Type: T2 – Background & Context
Owner: gicheol
Status: Done
Last Updated: 2026-03-17

---

## 1. Background Summary

- SBrain에서 프로젝트 파일을 탐색하면서 터미널 명령을 실행해야 할 때 외부 앱(Terminal.app, iTerm2)으로 전환 필요
- VS Code처럼 앱 내에서 바로 터미널을 사용할 수 있으면 워크플로우가 크게 개선됨

## 2. Problem Definition

- 대상 사용자: SBrain을 개발/운영 도구로 사용하는 개발자
- 불편 사항: 파일 탐색 → 외부 터미널 전환 → 컨텍스트 손실

## 3. Root Cause Hypothesis

1. SBrain이 뷰어/탐색 도구로만 설계되어 셸 실행 기능 부재
2. macOS 앱에서 터미널 에뮬레이터 구현은 별도 라이브러리 필요

## 4. Risk If Not Addressed

- 개발자 사용 시 항상 외부 터미널과 병행 → 앱 사용 빈도 저하

## 5. Target Outcome

- SBrain 내에서 zsh/bash 터미널을 여러 개 동시 실행 가능
- 선택된 프로젝트 폴더를 working directory로 자동 설정
- ANSI 컬러, vim, ssh 등 완전한 터미널 에뮬레이션
