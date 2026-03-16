# Background: Personal Workspace — SBrain 전용 기억 저장소

Type: T2 – Background & Context
Owner: gicheol
Status: Done
Last Updated: 2026-03-17

---

## 1. Background Summary

- SBrain은 현재 외부 프로젝트 폴더를 연결하여 읽기 전용 뷰어로만 사용 중
- 사용자가 SBrain 안에서 직접 문서를 작성하거나 편집할 수 있는 공간이 없음
- 프로젝트 폴더에서 발견한 중요 문서를 별도로 보관할 수단이 없음

## 2. Problem Definition

- 대상 사용자: SBrain을 개인 지식 관리 도구로 사용하는 개발자/연구자
- 발생 중인 불편:
  - 프로젝트 폴더는 읽기 전용이므로 메모나 정리 문서를 작성할 수 없음
  - 여러 프로젝트에서 발견한 핵심 문서를 한곳에 모을 수 없음
  - 외부 에디터를 별도로 열어 작업해야 하며 SBrain 워크플로우가 끊김

## 3. Root Cause Hypothesis

1. SBrain이 "뷰어"로만 설계되어 쓰기 기능이 아키텍처에 포함되지 않음
2. 프로젝트 폴더는 원본 보존이 필요하므로 직접 수정 대상이 아님
3. SBrain 전용 저장 공간(Vault) 개념이 부재

## 4. Risk If Not Addressed

- SBrain이 단순 뷰어에 머물러 사용 빈도 저하
- 사용자의 지식 관리 워크플로우가 SBrain 외부 도구에 의존
- 프로젝트 간 핵심 문서 수집/정리가 수동적이고 비효율적

## 5. Target Outcome

- SBrain 전용 폴더("기본 폴더")에서 마크다운/HTML 문서를 직접 생성·편집 가능
- 프로젝트 폴더의 파일을 기본 폴더로 복사하여 개인 지식 저장소에 보관 가능
- 기본 폴더도 Brain Map에 통합되어 기존 탐색·검색 인프라 활용 가능
