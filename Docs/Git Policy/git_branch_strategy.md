# Policy: Git Branch & Release Strategy

Type: T5 – Policy / Rule
Owner: gicheol
Status: Done
Last Updated: 2026-03-16

---

## 1. Policy Summary

- EduWorks 프로젝트의 Git 브랜치 전략, 릴리즈 프로세스, 배포 흐름을 정의한다.
- **Git Flow 변형 모델**을 채택하며, `main`(프로덕션) + `develop`(개발 통합) + 피처 브랜치 구조를 사용한다.
- 모든 팀원과 자동화 도구(Claude Code, Railway CI/CD)가 동일한 규칙을 따르도록 한다.

---

## 2. Scope

### 적용 대상

- EduWorks 리포지토리 (`hanmariyang/EduWorks`) 전체
- 백엔드(Django), 프론트엔드(Next.js) 모노레포 구조에 동일 적용

### 적용 시점

- 즉시 적용 (2026-03-16~)
- 기존 브랜치는 소급 적용하지 않으며, 신규 브랜치부터 적용

---

## 3. Branch Structure

### 3.1 영구 브랜치 (Protected Branches)

| 브랜치 | 역할 | 배포 대상 | 보호 수준 |
|--------|------|-----------|-----------|
| `main` | 프로덕션 릴리즈 | Railway Production | force-push 금지, PR 필수 |
| `develop` | 개발 통합 | Railway Dev (자동 배포) | force-push 금지, PR 권장 |

### 3.2 임시 브랜치 (Feature / Fix Branches)

| 브랜치 패턴 | 용도 | 분기 기준 | 병합 대상 |
|-------------|------|-----------|-----------|
| `{version}/{descriptive-name}` | 기능 개발, 버그 수정 | `develop` | `develop` |

**네이밍 규칙**

```
{version}/{descriptive-name}
```

- `version`: 현재 릴리즈 버전 (예: `v1.0.0`)
- `descriptive-name`: kebab-case, 기능 단위 설명
- 예시:
  - `v1.0.0/phase3-frontend-integration`
  - `v1.0.0/phase5-celery-automation`
  - `v1.0.3/task-schedule-generation-fix`

---

## 4. Workflow Rules

### 4.1 피처 브랜치 생성

```bash
# 1. develop 최신화
git checkout develop && git pull origin develop

# 2. 피처 브랜치 분기
git checkout -b v1.0.0/{descriptive-name}
```

- 반드시 `develop`에서 분기한다.
- `main`에서 직접 분기하지 않는다.
- 브랜치 생성 전 `develop`을 최신 상태로 pull 한다.

### 4.2 커밋 메시지 규칙

```
{type}: {description}
```

| type | 사용 시점 |
|------|----------|
| `feat` | 새 기능 추가 |
| `fix` | 버그 수정 |
| `refactor` | 리팩토링 (기능 변화 없음) |
| `docs` | 문서만 변경 |
| `chore` | 빌드·설정·패키지 변경 |

- 설명은 한국어 또는 영문 사용 가능
- 50자 이내 권장, 핵심 변경 사항을 명확히 기술
- 예시:
  - `feat: 트랙 생성 위저드 개선 — DB 저장 + 인원 배정 실제 API 연동`
  - `fix: JWT 쿠키 SameSite/Secure 직접 env var 오버라이드 지원`
  - `chore: Railway 프로덕션 배포 인프라 구성`

### 4.3 Pull Request 규칙

| 항목 | 규칙 |
|------|------|
| PR 대상 | `develop` (기본) |
| PR 제목 | `{version} {Feature Name}` 또는 커밋 메시지 형식 |
| Merge 방식 | Merge commit (기본) |
| 리뷰 | 1인 이상 권장 (소규모 팀 기준 셀프 리뷰 허용) |

- PR 본문에 변경 사항 요약을 포함한다.
- 관련 문서(T2~T7)가 있으면 PR 본문에 링크한다.

### 4.4 develop → main 병합 (릴리즈)

```bash
# develop → main PR 생성
gh pr create --base main --head develop --title "Release v{X.Y.Z}"
```

- `develop`이 안정 상태일 때만 `main`으로 병합한다.
- 병합 후 `main`에 버전 태그를 생성한다.

---

## 5. Release & Tagging

### 5.1 버전 체계

```
v{MAJOR}.{MINOR}.{PATCH}
```

| 구분 | 변경 시점 |
|------|----------|
| MAJOR | 대규모 구조 변경, 하위 호환 불가 |
| MINOR | 기능 추가, 하위 호환 유지 |
| PATCH | 버그 수정, 핫픽스 |

### 5.2 태그 생성

```bash
# main 브랜치에서 태그 생성
git tag v1.0.0
git push origin v1.0.0
```

- 태그는 `main` 병합 직후 생성한다.
- 태그명은 `v{MAJOR}.{MINOR}.{PATCH}` 형식을 따른다.

### 5.3 핫픽스 (긴급 수정)

긴급 프로덕션 버그 발생 시:

1. `develop`에서 핫픽스 브랜치 생성 → `{version}/hotfix-{description}`
2. 수정 후 `develop`으로 PR → 병합
3. `develop` → `main` 즉시 릴리즈

---

## 6. Deployment Strategy

### 6.1 배포 환경

| 환경 | 브랜치 | URL | 배포 방식 |
|------|--------|-----|-----------|
| Dev | `develop` | `eduworks-dev-backend-production.up.railway.app` | 자동 배포 (push 시) |
| Production | `main` | Railway Production | `main` 병합 시 자동 배포 |

### 6.2 배포 흐름

```
피처 브랜치 → PR → develop (자동 배포: Dev)
                       ↓
                develop → PR → main (자동 배포: Production)
                                ↓
                              태그 생성 (v{X.Y.Z})
```

### 6.3 배포 전 체크리스트

- [ ] `develop` 환경에서 기능 검증 완료
- [ ] 마이그레이션 파일 충돌 없음
- [ ] 환경 변수 변경 시 Railway 설정 동기화 완료
- [ ] 프론트엔드 빌드 타임 환경 변수(`NEXT_PUBLIC_*`) 확인

---

## 7. Branch Lifecycle

### 7.1 브랜치 생명 주기

```
생성 → 개발 → PR 생성 → 리뷰 → 병합 → 삭제
```

- 병합 완료된 피처 브랜치는 삭제한다.
- 원격 브랜치도 병합 후 삭제한다 (GitHub "Delete branch" 옵션 활용).
- 장기 미사용(2주 이상 활동 없음) 브랜치는 정리 대상으로 식별한다.

### 7.2 로컬 정리

```bash
# 병합 완료된 로컬 브랜치 정리
git branch --merged develop | grep -v "develop\|main" | xargs git branch -d

# 삭제된 원격 브랜치 참조 정리
git fetch --prune
```

---

## 8. Prohibited Actions

| 금지 행위 | 사유 |
|-----------|------|
| `main`에 직접 push | 프로덕션 안정성 보장 |
| `main`에 force-push | 히스토리 보존 |
| `develop`에 force-push | 팀원 브랜치 기반 보호 |
| 태그 삭제/이동 | 릴리즈 추적 무결성 |
| 피처 브랜치에서 `main` 직접 병합 | 우회 배포 방지 |

---

## 9. Branch Flow Diagram

```
main ─────────────────●────────────────●──────── (Production)
                      ↑                ↑
develop ──●──●──●──●──●──●──●──●──●──●──●────── (Dev Auto-deploy)
          ↑     ↑        ↑        ↑
          │     │        │        │
feature/A ●──●──┘        │        │
                         │        │
feature/B    ●──●──●─────┘        │
                                  │
hotfix/C              ●──●────────┘
```

---

## 10. Exceptions / FAQ

### Q. develop에 직접 커밋해도 되는 경우는?

- 단순 설정 변경(`chore`), 긴급 핫픽스 등 1~2 커밋 수준의 소규모 변경은 직접 커밋 허용한다.
- 3개 이상의 커밋이 필요한 작업은 반드시 피처 브랜치를 생성한다.

### Q. 버전 브랜치의 version은 언제 올리는가?

- `main`에 릴리즈 태그를 찍은 후, 다음 작업부터 새 버전을 사용한다.
- 동일 릴리즈 주기 내 모든 피처 브랜치는 같은 version prefix를 사용한다.

### Q. 충돌이 발생하면?

- 피처 브랜치에서 `develop`을 merge 하여 해결한다 (`rebase`보다 `merge` 권장).
- 충돌 해결 후 커밋 메시지: `fix: merge conflict 해결 ({설명})`
