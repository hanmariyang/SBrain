# /hotfix — SBrain 긴급 패치 릴리즈

사용법: `/hotfix {description}`
예시: `/hotfix crash-on-empty-terminal`

긴급 버그 수정 후 바로 패치 릴리즈를 수행한다.

## 인자

- `$ARGUMENTS` — 핫픽스 설명 (kebab-case). 인자가 없으면 사용자에게 물어본다.

## 실행 단계

### 1. 현재 버전 확인 + PATCH 증가

1. `app/project.yml`에서 현재 `MARKETING_VERSION` 읽기
2. PATCH 버전을 1 증가 (예: `0.5.0` → `0.5.1`)
3. 사용자에게 확인: "v{NEW_VERSION}으로 핫픽스 릴리즈합니다. 진행할까요?"

### 2. 핫픽스 브랜치 생성

```bash
git checkout develop && git pull origin develop
git checkout -b v{NEW_VERSION}/hotfix-{ARGUMENTS}
```

### 3. 수정 작업

사용자가 수정할 내용을 알려주면 코드를 수정한다.
수정 완료 후 커밋:
```
fix: {description}
```

### 4. develop 머지

```bash
git checkout develop
git merge v{NEW_VERSION}/hotfix-{ARGUMENTS} --no-edit
git push origin develop
```

### 5. /release 실행

버전 업데이트 → main 머지 → 태그 → CI 트리거까지 `/release {NEW_VERSION}` 과정을 실행한다.

### 6. 브랜치 정리

```bash
git branch -d v{NEW_VERSION}/hotfix-{ARGUMENTS}
```
