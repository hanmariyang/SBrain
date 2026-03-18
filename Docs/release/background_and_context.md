# Background: macOS App Distribution & Update Management

Type: T2 – Background & Context
Owner: gicheol
Status: Done
Last Updated: 2026-03-18

---

## 1. Background Summary

- SBrain은 현재 Xcode에서 직접 빌드하여 로컬에서만 실행하는 방식으로 사용 중
- 외부 사용자에게 배포하거나, 버전 업데이트를 자동으로 전달하는 구조가 없음
- 앱이 안정화됨에 따라 배포 파이프라인과 업데이트 관리 체계 수립이 필요

## 2. Problem Definition

- **대상**: SBrain macOS 앱 사용자 (본인 포함, 추후 외부 배포 대비)
- **발생 중인 불편**:
  - 매번 Xcode에서 빌드해야 실행 가능
  - 다른 Mac에 전달하려면 수동 복사 필요
  - 코드 서명이 없어 GateKeeper 경고 발생 ("확인되지 않은 개발자")
  - 업데이트 시 사용자가 수동으로 새 빌드를 받아야 함
- **비용/리스크**:
  - 배포 과정에서 빌드 설정 실수 가능
  - 서명/공증 없이 배포 시 macOS 보안 정책에 의해 실행 차단

## 3. Root Cause Hypothesis

1. Apple Developer Program 미등록 → Developer ID 인증서 없음 → 코드 서명/공증 불가
2. 빌드-서명-배포 자동화 파이프라인 부재 → 수동 빌드 의존
3. 앱 내 자동 업데이트 메커니즘 미구현 → 사용자가 매번 수동 다운로드

## 4. Risk If Not Addressed

- 외부 배포 시 GateKeeper가 앱 실행을 차단하여 사용자 이탈
- 버전 관리 혼란 (어떤 빌드가 최신인지 추적 불가)
- 보안 취약점 발견 시 긴급 패치 배포 경로 없음

## 5. Target Outcome

- `.dmg` 설치 파일을 통한 원클릭 설치 가능
- Apple 공증(Notarization) 완료로 GateKeeper 경고 없음
- 앱 내 자동 업데이트 알림 및 설치 지원
- GitHub tag push → 빌드 → 서명 → 공증 → 릴리즈 자동화
