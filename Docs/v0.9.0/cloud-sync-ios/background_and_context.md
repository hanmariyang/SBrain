# Background: SBrain v0.9.0 Cloud Sync & iOS Expansion

Type: T2 – Background & Context
Owner: gicheol
Status: Draft
Last Updated: 2026-03-24

---

## 1. Background Summary

SBrain v0.8.0은 macOS 데스크탑 앱으로 로컬 마크다운 파일을 3D Brain Map으로 시각화하는 기능을 제공한다.
그러나 **모든 데이터가 맥북 로컬에 갇혀 있어** 모바일에서 접근할 수 없으며,
VC 평가에서 **macOS 전용 = TAM 제한**, **시장 검증 부재**, **수익 모델 없음**이 치명적 약점으로 지적되었다.

iOS 확장을 위해 아키텍처를 검토한 결과, 기존 "로컬 파일 직접 편집" 워크플로우를 유지하면서
모바일에서 읽기/검색이 가능한 **"스냅샷 Push" 하이브리드 아키텍처**가 최적이라 판단했다.

---

## 2. Problem Definition

### 대상 사용자
- macOS에서 마크다운 노트를 관리하며, 이동 중 iPhone/iPad에서 조회하고 싶은 사용자

### 문제 1: 데이터가 맥북에 갇혀있다

| 데이터 | 저장 위치 | 모바일 접근 |
|--------|----------|------------|
| `.md` 파일 | `~/Documents/notes/` (맥북 로컬) | 불가 |
| `brain.db` (인덱스) | `backend/brain.db` (맥북 로컬 SQLite) | 불가 |
| Django API | `localhost:8765` | 불가 (로컬 네트워크 전용) |
| Slack/Calendar 인증 | 맥북 로컬 파일 | 불가 |

### 문제 2: 클라우드 전면 전환은 기존 워크플로우를 파괴한다

검토한 "옵션 B (클라우드 중앙 서버)" 방식의 문제:
- 파일을 매번 클라우드에 업로드해야 함 → 로컬 편집의 즉시성 상실
- VS Code, Obsidian 등 로컬 에디터와의 연동 끊김
- Note.path가 로컬 절대경로 → 상대경로 전환 필요 → 대규모 리팩토링
- 사용자 입장에서 "왜 파일을 올려야 하지?" → 제품 가치 훼손

### 문제 3: 시장 검증 인프라 부재

- 유저 분석(Analytics) 없음
- 크래시 리포팅 없음
- 테스트 커버리지 0%
- 공개 배포 채널 없음

---

## 3. Root Cause Hypothesis

### 가설 1: "로컬 퍼스트" 설계가 단일 디바이스를 전제했다
- Django를 macOS 앱의 child process로 실행하는 구조 자체가 1대 디바이스 전용
- 데이터 공유 레이어가 아예 존재하지 않음

### 가설 2: 데이터 이동이 아니라 데이터 미러링이 필요하다
- 사용자는 "파일을 옮기고 싶은 것"이 아니라 "밖에서도 보고 싶은 것"
- 원본은 맥북에, 읽기 전용 복제본을 클라우드에 두는 것이 자연스러움
- 이미 v0.8.0에서 `Note.content`에 파일 전체 내용이 DB에 저장됨 → 이 DB를 클라우드에 동기화하면 됨

### 가설 3: 기존 인프라를 최대한 활용해야 한다
- Railway Django가 이미 운영 중 (appcast 프록시, OAuth 콜백)
- v0.8.0의 FileMonitor + partial_ingest가 이미 파일 변경을 감지
- 기존 API(`/api/notes/`, `/api/graph/`, `/api/search/`)를 iOS에서 그대로 호출 가능

---

## 4. Risk If Not Addressed

### 사업 리스크
- macOS 전용으로는 TAM이 전체 PC의 ~15% → VC 투자 불가
- 모바일 없이는 "세컨드 브레인" 컨셉의 절반만 구현 → "항상 접근 가능" 가치 부재
- 시장 검증 없이 기능만 추가하면 방향성 잃을 위험

### 기술 리스크
- 나중에 iOS를 추가하면 아키텍처 전면 재설계 필요 → 지금이 비용이 가장 낮음
- 테스트 없이 리팩토링하면 기존 기능 깨짐 위험

### 경쟁 리스크
- Obsidian은 이미 5개 OS 지원 + 200만 사용자
- 모바일 없이는 경쟁 자체가 불가능

---

## 5. Target Outcome

| 항목 | 목표 상태 |
|------|----------|
| macOS 워크플로우 | **기존과 100% 동일** (로컬 파일 편집, 로컬 Django) |
| 클라우드 동기화 | macOS에서 변경 감지 시 Railway에 **자동 push** (content 기준) |
| iOS 앱 | TestFlight 배포. **읽기 + 검색 + 3D Brain Map** |
| 테스트 | 백엔드 핵심 API 커버리지 **70%+**, CI 자동 실행 |
| 분석 | TelemetryDeck으로 **3D 사용률, DAU** 측정 가능 |
| 공개 준비 | 랜딩 페이지 + GitHub public + README |
