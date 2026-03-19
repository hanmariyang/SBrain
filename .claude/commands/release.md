# /release — SBrain 릴리즈 자동화

사용법: `/release {version}`
예시: `/release 0.6.0`

아래 단계를 **순서대로, 각 단계가 성공한 후에만** 다음 단계를 진행한다.

## 인자

- `$ARGUMENTS` — 릴리즈 버전 번호 (예: `0.6.0`). 인자가 없으면 사용자에게 버전을 물어본다.

## 실행 단계

### 1. 사전 검증

```bash
# 현재 브랜치가 develop인지 확인
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "develop" ]; then
  echo "ERROR: develop 브랜치에서 실행해야 합니다. 현재: $BRANCH"
  exit 1
fi

# 워킹 트리가 깨끗한지 확인
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: 커밋되지 않은 변경사항이 있습니다."
  git status --short
  exit 1
fi

# develop 최신화
git pull origin develop
```

실패 시 사용자에게 알리고 중단한다.

### 2. 버전 업데이트

1. `app/project.yml`의 `MARKETING_VERSION`을 `$ARGUMENTS`로 업데이트
2. `CURRENT_PROJECT_VERSION`을 1 증가
3. XcodeGen 재생성: `cd app && xcodegen generate`
4. 빌드 확인: `xcodebuild -project SBrain.xcodeproj -scheme SBrain -configuration Release build`
5. 빌드 성공 시 커밋:
   ```
   chore: bump version to v{VERSION}
   ```

### 3. develop → main 머지

```bash
git checkout main
git pull origin main
git merge develop --no-edit
```

충돌 발생 시 사용자에게 알리고 중단한다.

### 4. 태그 생성 + 푸시

```bash
git tag v{VERSION}
git push origin main --tags
```

이 push가 GitHub Actions의 `release.yml` 워크플로우를 트리거한다.
워크플로우가 자동으로 수행하는 작업:
- Archive 빌드 (Release)
- Developer ID 코드 서명
- Apple Notarization (공증)
- .dmg 생성
- Sparkle appcast.xml 업데이트
- GitHub Release 게시

### 5. develop 복귀 + 동기화

```bash
git checkout develop
git merge main --no-edit
git push origin develop
```

### 6. CI 확인

```bash
gh run list --workflow=release.yml --limit 1
```

CI 실행 상태를 사용자에게 보여준다.
실행 중이면: "GitHub Actions에서 빌드 진행 중입니다. `gh run watch`로 모니터링할 수 있습니다."
완료되면: GitHub Release URL을 보여준다.

### 7. 완료 메시지

```
✅ v{VERSION} 릴리즈 완료
- 태그: v{VERSION}
- GitHub Actions: 빌드/서명/공증/DMG 생성 자동 진행 중
- Release URL: https://github.com/hanmariyang/SBrain/releases/tag/v{VERSION}
- 사용자 앱: 다음 실행 시 Sparkle이 자동 업데이트 감지
```
