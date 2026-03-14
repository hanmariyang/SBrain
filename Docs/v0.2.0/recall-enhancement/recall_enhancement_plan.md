# Plan: Recall (회상) Feature Enhancement

Type: T3 – Plan / Design
Owner: gicheol
Status: In Progress
Last Updated: 2026-03-14

---

## 1. Goal

Recall(회상) 기능을 "검색 결과 목록 표시"에서 **Brain Map 연동 + 시각적 피드백이 있는 통합 경험**으로 구체화한다.

**성공 기준**
1. 검색 시 Brain Map에서 매칭 뉴런이 하이라이트되어 공간적 맥락 제공
2. 검색 결과가 뷰 전환(List ↔ Brain Map) 시에도 유지됨
3. 검색 실패/빈 결과에 대한 사용자 피드백 제공
4. 선택된 프로젝트 기준으로 검색 결과 필터링

---

## 2. Background (현재 문제)

### 현재 구현 상태
- 백엔드: voyage-3 임베딩 + sqlite-vec 벡터 검색 ✅ 완성
- 프론트엔드: RecallBar 입력 + RecallResultList 표시 ✅ 동작
- 결과 클릭 → 파일 선택 → MemoryDetailView 표시 ✅ 동작

### 문제점

| # | 문제 | 영향 |
|---|------|------|
| 1 | Brain Map에서 검색 결과 시각화 없음 | 검색과 시각화가 분리된 경험 |
| 2 | List↔Brain Map 전환 시 결과 사라짐 | 맥락 유실 |
| 3 | 검색 실패 시 무한 로딩처럼 보임 | 사용자 혼란 |
| 4 | 프로젝트 필터링 미적용 | 다른 프로젝트 결과가 섞임 |
| 5 | 결과 카운트 미표시 | 규모 파악 불가 |

---

## 3. Design

### 3.1 Brain Map 검색 하이라이트

검색 결과가 있을 때 Brain Map의 매칭 뉴런에 시각적 하이라이트 적용:
- 매칭 뉴런: 밝은 글로우 + 크기 증가 + 전체 불투명
- 비매칭 뉴런: 어둡게(dim) 처리 → 매칭 결과가 시각적으로 돋보임
- 시냅스: 매칭 뉴런 간 시냅스만 강조

```
검색 전:  모든 뉴런 동일 표현
검색 중:  매칭 뉴런 → 밝은 글로우 + 펄스
          비매칭 뉴런 → opacity 20%로 dim
          매칭 간 시냅스 → 강조
          비매칭 시냅스 → 거의 투명
검색 해제: 원래 상태로 복귀
```

### 3.2 검색 결과 상태 유지

- `searchResults`는 뷰 전환과 무관하게 NoteStore에 유지 (현재도 그러함)
- Brain Map 뷰에서도 `searchResults`를 참조하여 하이라이트 적용
- 검색 결과 경로 Set을 BrainCanvas3D에 전달

### 3.3 에러 및 빈 결과 피드백

- 검색 실패 → RecallBar 아래 "검색에 실패했습니다" 표시
- 빈 결과 → "검색 결과가 없습니다" 표시
- 백엔드 미가동 → "백엔드 연결 필요 (로컬 검색 불가)" 표시

### 3.4 프로젝트 필터링

- `selectedProjectId != nil`이면 검색 결과에서 해당 프로젝트 경로만 표시
- 백엔드는 전체 검색 → 프론트엔드에서 필터링 (백엔드 변경 없음)

### 3.5 결과 카운트 및 UX

- RecallBar에 결과 수 배지 표시
- 검색 중 스피너 + "회상 중..." 텍스트

---

## 4. Implementation Plan

### Step 1: NoteStore 검색 상태 보강
- `searchError: String?` 추가
- `filteredSearchResults: [SearchResult]` computed (프로젝트 필터)
- `searchResultPaths: Set<String>` computed (Brain Map용)

### Step 2: RecallBar UX 개선
- 결과 카운트 배지
- 에러/빈 결과 메시지

### Step 3: Brain Map 검색 하이라이트
- `BrainCanvas3D`에 `searchResultPaths: Set<String>` 전달
- 매칭 뉴런: 밝은 글로우 + 크기 1.5x
- 비매칭 뉴런: dim (opacity 0.15)
- 시냅스도 동일 로직

### Step 4: RecallResultList 개선
- 프로젝트 필터 적용
- 결과 없음 / 에러 상태 표시

---

## 5. Open Issues

- [ ] 실시간 검색(타이핑 중 자동 검색) 도입 여부 — API 비용 고려
- [ ] 검색 히스토리 저장 여부
- [ ] Brain Map에서 매칭 뉴런 자동 포커스(카메라 이동) 여부
