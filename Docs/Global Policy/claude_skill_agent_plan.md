# Plan: Claude Code Skill & Agent Architecture

Type: T3 – Plan / Design
Owner: gicheol
Status: Draft
Last Updated: 2026-02-24

---

## 1. Goal

Claude Code 기반 개발 워크플로우를 문서 정책(T1~T7)과 완전히 연동된 **스킬 + 서브에이전트 + 통합 스킬** 3계층 시스템으로 구축한다.

**성공 기준**
1. 모든 스킬 호출이 반드시 특정 T-타입 문서 생성으로 귀결된다.
2. 각 서브에이전트는 독립 실행 가능하며, 통합 스킬로도 오케스트레이션된다.
3. T2(문제 정의) 없이 T3(설계)로 진행하는 경로가 차단된다.
4. `/project:run` 단일 명령으로 전체 파이프라인(T2→T1)이 순차 실행된다.

---

## 2. Scope

### In Scope

- `.claude/commands/` 개별 스킬 파일 7개
- `.claude/agents/` 서브에이전트 파일 6개
- 통합 스킬 (`/project:run`) 1개
- CLAUDE.md Gate Rules 블록

### Out of Scope

- CI/CD 자동화 연동
- 기존 브랜치 문서 소급 적용
- Cursor IDE 전용 프롬프트 (별도 정책 적용)

---

## 3. 시스템 구조

서브에이전트는 **복잡한 구조적 추론이 필요한 T2 단 하나**만 사용한다.
나머지 T-타입은 스킬 파일 내 프롬프트로 메인 Claude가 직접 처리한다.
이유: 메인 세션이 이미 전체 컨텍스트를 보유하므로 별도 에이전트 실행은 토큰 낭비다.

```
┌─────────────────────────────────────────────────────┐
│  Layer 1: Skills (사용자 진입점)                      │
│  .claude/commands/                                   │
│  /project:define  /project:plan  /project:spec       │
│  /project:log     /project:validate  /project:wrap   │
│  /project:run  ← 통합 스킬                           │
└──────┬───────────────────────────────────────────────┘
       │                         │
       │ /project:define만       │ 나머지 스킬
       │ Task tool 호출           │ 메인 Claude 직접 처리
       ▼                         ▼
┌──────────────────┐   ┌────────────────────────────┐
│  Sub-Agent (1개) │   │  스킬 내 프롬프트 직접 실행  │
│  .claude/agents/ │   │  T3 / T4 / T5 / T6 / T7   │
│  problem_framing │   │  T1 (wrap)                 │
│  _agent.md (T2)  │   └──────────────┬─────────────┘
└────────┬─────────┘                  │
         │                            │
         └──────────────┬─────────────┘
                        ▼
          ┌─────────────────────────┐
          │  Documents (산출물)      │
          │  note/operation/{branch} │
          │  T1 T2 T3 T4 T5 T6 T7  │
          └─────────────────────────┘
```

---

## 4. User Scenarios

### Scenario 1: 개별 스킬 실행 (단계별 수동 제어)

```
사용자: /project:define 학생 미배정 D30 문제
→ Problem Framing Agent 실행
→ T2 문서 생성 및 Decision Gate 항목 출력
→ 사용자가 "설계 진행" 확인

사용자: /project:plan 미배정 알림 시스템
→ Gate 1 확인 (T2 존재 여부)
→ Design Agent 실행
→ T3 문서 생성

사용자: /project:spec
→ Gate 2 확인 (T3 존재 여부)
→ Spec Agent 실행 → T4 생성

... 이하 동일 패턴
```

### Scenario 2: 통합 스킬 실행 (자동 파이프라인)

```
사용자: /project:run 학생 미배정 D30 문제

→ [Step 1] Problem Framing Agent → T2 생성 → 사용자 확인 대기
→ 사용자: "진행"
→ [Step 2] Design Agent → T3 생성
→ [Step 3] Spec Agent → T4 생성
→ [Step 4] Execution Agent → T6 초안 생성 (실행 전 템플릿)
→ [Step 5] Validation Agent → T7 시나리오 생성
→ [Step 6] Summary Agent → T1 생성
→ 전체 파이프라인 완료 리포트 출력
```

### Scenario 3: Gate 차단

```
사용자: /project:plan (T2 없이)
→ "T2 문서가 없습니다."
→ "먼저 /project:define [문제명] 을 실행하세요."
→ 실행 중단
```

---

## 5. Design Principles

1. **단일 책임**: 각 스킬은 정확히 하나의 T-타입 문서만 생성한다.
2. **게이트 우선**: 선행 문서 없이 후속 스킬 실행을 허용하지 않는다.
3. **정책 위임**: 문서 형식은 Global Policy에 위임한다. 스킬 파일에 형식을 중복 정의하지 않는다.
4. **에이전트 독립성**: 각 서브에이전트는 단독 실행과 통합 실행 모두 지원한다.
5. **경로 명시**: 각 스킬은 출력 경로를 명시적으로 지정한다. 경로 추론 금지.
6. **사용자 확인 게이트**: T2 → T3 전환 시 반드시 사용자 확인을 거친다.

---

## 6. Structure / Flow

### 6.1 파일 시스템 전체 구조

```
.claude/
├── commands/                        ← 사용자 호출 스킬 (7개)
│   ├── define.md                    → /project:define   (T2, Sub-Agent 호출)
│   ├── plan.md                      → /project:plan     (T3, 메인 직접 처리)
│   ├── spec.md                      → /project:spec     (T4, 메인 직접 처리)
│   ├── log.md                       → /project:log      (T6, 메인 직접 처리)
│   ├── validate.md                  → /project:validate (T7, 메인 직접 처리)
│   ├── wrap.md                      → /project:wrap     (T1, 메인 직접 처리)
│   └── run.md                       → /project:run      (통합, 메인 직접 처리)
└── agents/                          ← 서브에이전트 (1개만)
    └── problem_framing_agent.md     → T2 전담 (구조적 분석 필요)
```

**서브에이전트를 T2에만 사용하는 이유**

| T-타입 | 처리 방식 | 이유 |
|--------|---------|------|
| T2 | Sub-Agent | 증상/원인 분리, KPI 연결, Decision Gate 생성 등 복잡한 구조적 추론 필요 |
| T3 | 메인 직접 | T2 컨텍스트가 이미 메인 세션에 있음 |
| T4 | 메인 직접 | T3 기반 구조화 작업, 템플릿 채우기 수준 |
| T6 | 메인 직접 | 사용자 제공 이슈를 템플릿에 기록하는 수준 |
| T7 | 메인 직접 | T3 시나리오를 검증 형식으로 변환, 메인에서 충분 |
| T1 | 메인 직접 | 메인 세션이 T2~T7 전체를 이미 보유 |

### 6.2 스킬 → 처리 방식 → 문서 매핑

| 스킬 | 처리 방식 | T-타입 | 출력 경로 패턴 | 선행 조건 |
|------|---------|--------|-------------|---------|
| `/project:define` | Sub-Agent 호출 | T2 | `01_overview/background_and_context.md` | 없음 |
| `/project:plan` | 메인 직접 처리 | T3 | `02_{scope}/plan.md` | T2 존재 |
| `/project:spec` | 메인 직접 처리 | T4 | `02_{scope}/specification.md` | T3 존재 |
| `/project:log` | 메인 직접 처리 | T6 | `02_{scope}/execution_log_{name}.md` | T3 존재 |
| `/project:validate` | 메인 직접 처리 | T7 | `05_validation/{name}.md` | T6 존재 |
| `/project:wrap` | 메인 직접 처리 | T1 | `01_overview/README.md` | T7 존재 |
| `/project:run` | 메인 직접 처리 | T2→T1 | 위 경로 전체 | 없음 |

### 6.3 Gate Rules 상세

```
Gate 1 (/project:plan 실행 조건)
  확인 대상: 01_overview/background_and_context.md 존재 여부
  차단 메시지: "T2 문서 없음. /project:define [문제명] 실행 필요"

Gate 2 (/project:spec, /project:log 실행 조건)
  확인 대상: 02_{scope}/plan.md 존재 여부
  차단 메시지: "T3 문서 없음. /project:plan [기능명] 실행 필요"

Gate 3 (/project:validate 실행 조건)
  확인 대상: T6 문서 1개 이상 존재 여부
  차단 메시지: "T6 문서 없음. /project:log 실행 필요"

Gate 4 (/project:wrap 실행 조건)
  확인 대상: T7 문서 1개 이상 존재 여부
  차단 메시지: "T7 문서 없음. /project:validate 실행 필요"
```

### 6.4 /project:run 통합 스킬 흐름

```
[통합 스킬 실행 흐름]

START: /project:run {problem_description}
  │
  ├─ Step 1: problem_framing_agent 호출 (Task tool)
  │    입력: {problem_description}
  │    출력: T2 문서 생성
  │    → 사용자 확인 요청 (Decision Gate)
  │    → "진행" 응답 시만 Step 2 진행
  │
  ├─ Step 2: design_agent 호출
  │    입력: T2 문서 내용 참조
  │    출력: T3 문서 생성
  │
  ├─ Step 3: spec_agent 호출
  │    입력: T3 문서 내용 참조
  │    출력: T4 문서 생성
  │
  ├─ Step 4: execution_agent 호출
  │    입력: T3, T4 문서 참조
  │    출력: T6 템플릿 생성 (실제 로그는 실행 후 채움)
  │
  ├─ Step 5: validation_agent 호출
  │    입력: T3, T4 문서 참조
  │    출력: T7 시나리오 문서 생성
  │
  └─ Step 6: summary_agent 호출
       입력: T2~T7 전체 참조
       출력: T1 문서 생성
       → 전체 완료 리포트 출력
```

---

## 7. 서브에이전트 설계 (1개)

### 7.1 Problem Framing Agent (T2 전담)

**역할**: 문제를 구조적으로 분석하고 T3 진행 여부를 판단하는 게이트

**Sub-Agent로 분리하는 이유**
- 증상(Symptom)과 근본 원인(Root Cause) 분리는 집중된 추론 필요
- Decision Gate 결과가 이후 T3~T7 전체 방향을 결정함
- 메인 컨텍스트와 분리하여 문제 정의에만 집중

**입력**: 사용자가 제공한 자유 텍스트 문제 설명

**출력**: `background_and_context.md` (T2) + Decision Gate 제시

**내부 처리 순서**
```
1. 입력 텍스트에서 증상(Symptom)과 근본 원인(Root Cause) 분리
2. 영향 범위(사용자 / 운영 / KPI) 분석
3. 해결하지 않을 경우 리스크 도출
4. Decision Gate 항목 생성
5. T2 문서 작성 및 저장
6. 메인 Claude에 Decision Gate 결과 반환
```

**자가 체크리스트** (문서 저장 전 검증)
- [ ] 증상과 근본 원인을 분리했는가
- [ ] KPI 또는 운영 영향을 명시했는가
- [ ] 해결하지 않을 경우 리스크를 기술했는가
- [ ] Decision Gate 항목(진행 / 실험 필요 / 보류 / 문제 아님)을 포함했는가
- [ ] 배경, 문제 정의, 목표 상태가 모두 작성됐는가

---

### 7.2 메인 Claude 직접 처리 (T3~T1)

서브에이전트 없이 스킬 파일 내 프롬프트 지시만으로 메인 Claude가 직접 처리한다.
메인 세션이 이미 T2 결과와 전체 프로젝트 컨텍스트를 보유하기 때문에 별도 에이전트가 불필요하다.

| T-타입 | 메인 처리 시 핵심 지시 |
|--------|-------------------|
| T3 | T2의 Target Outcome → Goal 변환, In/Out Scope 분리, Decision Points 추천안 포함 |
| T4 | T3 구성 요소 → 필드/API 명세, 제약 조건, Sample JSON 포함 |
| T6 | 사용자 제공 이슈 → Severity 분류, Expected vs Actual, 임시/영구 해결책 분리 |
| T7 | T3 시나리오 → 검증 절차, Pass Criteria 정량화, 운영 가능 여부 판단 포함 |
| T1 | 현재 컨텍스트 전체 → One-line Conclusion, Decisions, Next Actions 3개 |

---

## 8. 스킬 파일 내부 구조 (공통 형식)

각 `.claude/commands/*.md` 파일은 아래 구조를 따른다.

```markdown
# Skill: {skill_name}

## Trigger
/project:{name} {arguments}

## Gate Check
- 선행 문서 경로 확인
- 없으면 차단 메시지 출력 후 중단

## Agent Invocation
Task tool로 .claude/agents/{agent_name}.md 호출
입력 컨텍스트: {인자 + 선행 문서 내용}

## Output
- 문서 타입: T{n}
- 저장 경로: {path_pattern}
- 파일명 규칙: {naming_rule}

## Post Action
- 저장 완료 메시지 출력
- 다음 권장 스킬 안내
```

---

## 9. Decision Points

### DP1: `/project:define` 인자 형식

| 선택지 | 설명 |
|--------|------|
| **A) 자유 텍스트 (추천)** | `/project:define 학생 미배정 D30 문제` → 유연성 높음 |
| B) 구조화 인자 | `--scope=학생 --problem=미배정` → 파싱 복잡 |

→ **A 선택**: Problem Framing Agent가 내부에서 구조화 처리

### DP2: Gate 위반 시 동작

| 선택지 | 설명 |
|--------|------|
| **A) 경고 후 차단 (추천)** | 선행 문서 경로 안내 후 실행 중단 |
| B) 경고 후 확인 대기 | 사용자 "강제 진행" 선택 시 허용 |

→ **A 선택**: 정책 일관성 우선. 예외 필요 시 CLAUDE.md override 명시

### DP3: 통합 스킬 중단 지점

| 선택지 | 설명 |
|--------|------|
| **A) T2 → T3 전환 시 1회만 확인 (추천)** | 사용자 부담 최소화 |
| B) 각 Step마다 확인 | 세밀한 제어, 사용 불편 |

→ **A 선택**: T2 Decision Gate만 필수 확인, 이후 자동 진행

### DP4: T5(Policy) 스킬 독립 여부

| 선택지 | 설명 |
|--------|------|
| **A) CLAUDE.md 인라인 (추천)** | 비정기 사용, 별도 파일 불필요 |
| B) `policy.md` 스킬 파일 생성 | 사용 빈도 낮음 |

→ **A 선택**: 추후 사용 빈도 증가 시 분리

---

## 10. Open Issues

- [ ] 브랜치별 문서 경로 자동 감지 방식 미정 (현재 사용자가 브랜치 컨텍스트 수동 제공)
- [ ] 동일 브랜치 내 복수 T3 문서 발생 시 네이밍 충돌 방지 기준 미정
- [ ] `/project:wrap` 실행 시 기존 T1 덮어쓰기 vs 버전 관리 정책 미정
- [ ] 서브에이전트 간 문서 참조 방식 (파일 Read vs 컨텍스트 전달) 미정
- [ ] 통합 스킬 실행 중 특정 Step 실패 시 재시작 지점 처리 방식 미정
