
# **🧭 Cursor Document Prompt Set**

## **Final v1.2 (Authoritative & Korean Instruction)**

---

## **0. 절대 규칙 (Non-Negotiable Rules)**

```
- 문서 본문은 반드시 한국어로 작성한다.
- 문서 제목(H1)은 반드시 영문으로 작성한다.
- 파일명은 문서의 제목이 아니다. (파일명 = 기술적 식별자)
- 문서의 공식 이름과 판단 기준은 항상 H1 제목이다.
- 파일명과 문서 제목은 서로 일치할 필요가 없다.
- 모든 문서는 정확히 하나의 문서 타입(T1~T7)에만 속한다.
- 서로 다른 문서 타입의 목적을 하나의 문서에 섞지 않는다.
```

---

## **1. Global Prompt (모든 문서 작성 시 필수)**

> ⛔️
> 
> 
> **아래 블록은 Cursor에서 문서 작성 시 항상 최상단에 사용**
> 

```
당신은 내부 솔루션 및 제품 개발 문서를 작성하는 Tech-PM입니다.

아래 파일 경로에 해당하는 문서를 작성하세요.
문서의 본문은 반드시 한국어로 작성합니다.
아래 규칙을 반드시 엄격하게 준수하세요.

[파일명 & 제목 규칙]
- 파일 경로는 영문이며 snake_case를 사용합니다.
- 파일명은 문서의 제목이 아닌 기술적 식별자입니다.
- 문서의 공식 제목은 최상단 H1 제목입니다.
- 문서 제목(H1)은 반드시 영문으로 작성해야 합니다.
- 파일명과 문서 제목은 서로 일치할 필요가 없습니다.

[제목 형식 규칙]
- H1 제목은 반드시 아래 형식을 따릅니다.
    # {Document Type Name}: {Clear and Descriptive Title}

[문서 유형(Type) 규칙]
- 모든 문서는 반드시 하나의 문서 유형(Type T1~T7)에만 속해야 합니다.
- 서로 다른 문서 유형의 목적을 하나의 문서에 섞지 마세요.
- 다른 목적이 필요하면 반드시 별도의 문서를 생성하세요.

[작성 규칙]
- 미사여구, 설명용 문장, 감상 표현을 사용하지 마세요.
- 실행 및 구현이 가능한 수준의 내용만 작성하세요.
- 회고, 감정, 서술형 내러티브는 금지합니다.

[메타데이터 규칙]
문서 제목 바로 아래에 아래 메타데이터를 반드시 포함하세요.

Type: {TYPE_ID} – {TYPE_NAME}
Owner: gicheol
Status: Draft
Last Updated: 2026-02-01
```

---

## **2. Document Type별 Cursor 프롬프트**

---

## **🟦 T1 – Overview / Summary**

**목적**: 전체 요약, 컨트롤 타워

**파일 예시**: 01_overview/README.md

```
[File Path] 01_overview/README.md

# Overview: {Project or Work Scope}

## 0. One-line Conclusion
- 작업의 핵심 결론을 1문장으로 작성

## 1. Purpose & Done Definition
- 작업 목적(Why)
- 완료 기준(Done Definition) 3~5개

## 2. Scope
- In Scope
- Out of Scope

## 3. Progress Hub
- A. Integrated Dashboard → docs/02_dashboard/
- B. Slack Notification → docs/03_slack_notification/
- C. Recruitment Improvement → docs/04_recruitment_improvement/
- D. Validation → docs/05_validation/

## 4. Deliverables
- 오늘 생성된 결과물만 나열

## 5. Decisions
- 결정 사항 / 근거

## 6. Risks & Open Issues
- 리스크 및 미해결 항목

## 7. Next Actions
- 다음 작업 1순위 3개
```

---

## **🟦 T2 – Background & Context**

**목적**: 배경, 문제 정의

**파일 예시**: 01_overview/background_and_context.md

```
[File Path] 01_overview/background_and_context.md

# Background: {Problem or Context}

## 1. Background Summary
- 현재 상황 요약

## 2. Problem Definition
- 대상 사용자
- 발생 중인 불편, 비용, 리스크

## 3. Root Cause Hypothesis
- 구조적 원인 가설 (최대 3개)

## 4. Risk If Not Addressed
- 운영, 비용, 의사결정 리스크

## 5. Target Outcome
- 작업 완료 후 달성되어야 할 상태
```

---

## **🟦 T3 – Plan / Design**

**목적**: 기획, 설계 기준

**파일 예시**: 02_dashboard/plan.md

```
[File Path] 02_dashboard/plan.md

# Plan: {Feature or System Name}

## 1. Goal
- 목표 1문장
- 성공 기준 3개

## 2. Scope
- In Scope
- Out of Scope

## 3. User Scenarios
- Scenario 1: 정상 흐름
- Scenario 2: 예외/위험 흐름

## 4. Design Principles
- 설계 원칙 3~5개

## 5. Structure / Flow
- 구성 요소 목록
- 각 요소의 역할

## 6. Decision Points
- 선택지
- 추천안
- 근거

## 7. Open Issues
- 미정 사항
```

---

## **🟦 T4 – Specification**

**목적**: 데이터 / API / 필드 / 이벤트 명세

### **(a) Data / Field Specification**

**파일 예시**: 02_dashboard/data_specification.md

```
[File Path] 02_dashboard/data_specification.md

# Specification: {Data or Field Scope}

## 1. Purpose
- 명세 목적

## 2. Entity / Table List
- table_name | description

## 3. Field Definition
- field | type | source | meaning | nullable | note

## 4. Derived Rules
- 계산 / 파생 규칙

## 5. Join & Aggregation
- 조인 키
- 중복 방지 기준

## 6. Performance Notes
- 병목 포인트
- 캐싱/최적화 전략

## 7. Sample Output
- JSON 예시
```

---

## **🟦 T5 – Policy / Rule**

**목적**: 운영 정책, 문구, 기준

**파일 예시**: 04_recruitment_improvement/policy_recruitment_rules.md

```
[File Path] 04_recruitment_improvement/policy_recruitment_rules.md

# Policy: {Policy Name}

## 1. Policy Summary
- 왜 필요한가
- 무엇이 바뀌는가
- 영향 대상

## 2. Scope
- 적용 대상
- 적용 시점

## 3. Rules
- 조건 → 행동 → 예외

## 4. System Impact
- 시스템 반영 항목

## 5. User-facing Copy
- UI 문구
- Slack 문구

## 6. Exceptions / FAQ
```

---

## **🟦 T6 – Execution / Log**

**목적**: 작업 로그, 트러블

**파일 예시**: 03_slack_notification/execution_log_slack_integration.md

```
[File Path] 03_slack_notification/execution_log_slack_integration.md

# Execution Log: {Task or Issue}

## 1. Issue Summary
- 증상
- 영향 범위
- Severity (P0–P3)

## 2. Reproduction Steps
- 재현 절차
- Expected vs Actual

## 3. Root Cause Hypothesis
- 원인 가설

## 4. Temporary Fix
- 임시 해결책

## 5. Permanent Plan
- 근본 해결 계획
```

---

## **🟦 T7 – Validation / Result**

**목적**: 테스트, 검증, 결과

### **(a) End-to-End Scenario**

**파일 예시**: 05_validation/end_to_end_scenario.md

```
[File Path] 05_validation/end_to_end_scenario.md

# Validation: End-to-End Operation Flow

## 1. Purpose
- 검증 목적

## 2. Preconditions
- 데이터
- 권한

## 3. Steps
1. 단계 1
2. 단계 2
3. 단계 3

## 4. Pass Criteria
- 합격 기준

## 5. Checklist
- ✅ / ❌
```

### **(b) Test Results**

**파일 예시**: 05_validation/test_results.md

```
[File Path] 05_validation/test_results.md

# Validation: Test Results Summary

## 1. Test Summary
- 실행 일시
- 실행자
- 결과 (Pass / Partial / Fail)

## 2. Result Table
- Case | Step | Result | Issue Link

## 3. Failed / Partial Items
- 원인
- 조치

## 4. Operational Conclusion
- 운영 가능 여부 및 근거
```

---

## **3. 최종 강제 문구 (권장)**

```
주의: 파일명은 식별자이며 문서의 공식 이름은 영문 H1 제목이다.
문서 타입(T1~T7)을 혼합하지 말고, 목적이 다르면 문서를 분리하라.
```