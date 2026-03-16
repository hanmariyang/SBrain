# ──────────────────────────────────────────────────────────────
# SBrain — Makefile
# ──────────────────────────────────────────────────────────────

.PHONY: help up down restart logs backend-logs \
        build rebuild status \
        app xcode \
        backend-shell \
        setup clean

# ── 기본 ────────────────────────────────────────────────────
help: ## 도움말
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ── Docker 인프라 ───────────────────────────────────────────
up: ## 백엔드 시작
	docker compose up -d
	@echo ""
	@echo "  SBrain 백엔드: http://localhost:8765/api/status/"
	@echo ""

down: ## 전체 종료
	docker compose down

restart: ## 백엔드 재시작 (코드 변경 후)
	docker compose restart backend

rebuild: ## 백엔드 이미지 재빌드 + 시작
	docker compose up -d --build backend

build: ## Docker 이미지 빌드만
	docker compose build

status: ## 컨테이너 상태 확인
	docker compose ps

logs: ## 전체 로그 (follow)
	docker compose logs -f --tail=50

backend-logs: ## 백엔드 로그만
	docker compose logs -f --tail=50 backend

# ── Shell 접속 ──────────────────────────────────────────────
backend-shell: ## 백엔드 컨테이너 shell
	docker compose exec backend bash

# ── macOS 앱 ────────────────────────────────────────────────
app: up ## 앱 빌드 + 실행 (백엔드 자동 시작)
	cd app && xcodegen generate && \
	xcodebuild -project SBrain.xcodeproj -scheme SBrain \
		-destination 'platform=macOS' build && \
	open "$$(xcodebuild -project SBrain.xcodeproj -scheme SBrain \
		-showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | \
		awk '{print $$3}')/SBrain.app"

xcode: ## Xcode 프로젝트 재생성 + 열기
	cd app && xcodegen generate && open SBrain.xcodeproj

# ── 초기 설정 ───────────────────────────────────────────────
setup: ## 최초 설정 (env 복사 + Docker 빌드 + 시작)
	@echo "SBrain 초기 설정 시작..."
	@if [ ! -f backend/.env ]; then \
		cp backend/.env.example backend/.env; \
		echo "  backend/.env 생성됨 — API 키를 입력하세요"; \
	else \
		echo "  backend/.env 이미 존재"; \
	fi
	docker compose up -d --build
	@echo ""
	@echo "  설정 완료!"
	@echo ""
	@echo "  다음 단계:"
	@echo "    1. backend/.env 에 ANTHROPIC_API_KEY 설정"
	@echo "    2. make xcode  — Xcode 열기"
	@echo "    3. make app    — 빌드 + 실행"
	@echo ""

clean: ## Docker 전체 정리
	docker compose down -v
	@echo "  컨테이너 삭제 완료"

# ── 로컬 개발 (Docker 없이) ─────────────────────────────────
local-backend: ## 로컬에서 백엔드 직접 실행
	cd backend && ../venv/bin/python manage.py runserver 8765 --noreload

local-install: ## 로컬 Python 의존성 설치
	pip install -r backend/requirements.txt
