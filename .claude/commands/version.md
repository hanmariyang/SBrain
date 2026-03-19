# /version — 현재 버전 및 릴리즈 상태 확인

아래 정보를 수집하여 한눈에 보여준다.

## 실행 단계

### 1. 현재 버전 확인

`app/project.yml`에서 `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`을 읽는다.

### 2. Git 태그 목록

```bash
git tag --sort=-version:refname | head -5
```

최근 5개 릴리즈 태그를 보여준다.

### 3. 현재 브랜치 + 상태

```bash
git branch --show-current
git log --oneline -3
```

### 4. GitHub Release 최신 확인

```bash
gh release list --limit 3
```

### 5. 결과 출력

아래 형식으로 출력한다:

```
📦 SBrain 버전 정보
─────────────────────────
현재 버전:     v{MARKETING_VERSION} (빌드 {CURRENT_PROJECT_VERSION})
현재 브랜치:   {branch}
최신 태그:     {latest tag}
─────────────────────────
최근 릴리즈:
  {gh release list 결과}
─────────────────────────
최근 커밋:
  {git log --oneline -3 결과}
```
