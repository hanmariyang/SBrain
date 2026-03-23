# Slack & Google Calendar Integration — Background & Context

Type: T2 – Background & Context
Owner: gicheol
Status: In Progress
Last Updated: 2026-03-23

---

## 문제 정의

### 현재 상황
SBrain은 로컬 마크다운/HTML 파일을 저장·인덱싱하고 3D 뇌 시각화로 탐색하는 **개인 지식 관리 도구**이다. 그러나 일상 업무의 핵심 정보는 파일 뿐 아니라 **Slack 메시지**와 **일정**에도 분산되어 있다.

### 해결해야 할 문제

1. **Slack 메시지 과부하**
   - 하루 수십 건의 멘션/DM/채널 메시지 중 "내가 처리해야 할 것"을 식별하는 데 시간 소요
   - 컨텍스트 스위칭 비용이 높고, 중요 요청이 누락될 위험

2. **일정 관리 단절**
   - Google Calendar를 별도 앱/웹에서 확인해야 하는 불편
   - Slack에서 발생한 미팅/마감 요청을 수동으로 캘린더에 옮겨야 함

3. **통합 워크스페이스 부재**
   - 노트(Memory) + 메시지 + 일정이 각각 다른 도구에 흩어져 있음
   - SBrain을 "두 번째 뇌"로 쓰려면 이들을 한 곳에서 관리할 수 있어야 함

### 기대 효과
- SBrain 하나에서 노트 + Slack + 캘린더를 통합 관리
- AI 분석으로 Slack 메시지 자동 분류·요약·답변 초안 생성
- Slack 메시지에서 추출한 일정을 원클릭으로 Google Calendar에 등록
- 컨텍스트 스위칭 최소화 → 업무 생산성 향상

---

## 참고 자료

- `slack_agent_architecture.docx` — Slack Action Agent 컨셉 디자인 (팀스파르타 EduOps)
- 원본 설계는 Claude.ai Artifact + MCP 서버 기반이나, SBrain에서는 **네이티브 macOS 앱 + Django 백엔드**로 재구현
