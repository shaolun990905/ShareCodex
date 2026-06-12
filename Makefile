.PHONY: build build-backend build-frontend build-datamanagementd test test-backend test-frontend test-frontend-critical test-datamanagementd secret-scan \
        deploy deploy-init deploy-down deploy-restart deploy-logs deploy-status deploy-nginx

# =============================================================================
# Build
# =============================================================================

FRONTEND_CRITICAL_VITEST := \
	src/views/auth/__tests__/LinuxDoCallbackView.spec.ts \
	src/views/auth/__tests__/WechatCallbackView.spec.ts \
	src/views/user/__tests__/PaymentView.spec.ts \
	src/views/user/__tests__/PaymentResultView.spec.ts \
	src/components/user/profile/__tests__/ProfileInfoCard.spec.ts \
	src/views/admin/__tests__/SettingsView.spec.ts

# 一键编译前后端
build: build-backend build-frontend

# 编译后端（复用 backend/Makefile）
build-backend:
	@$(MAKE) -C backend build

# 编译前端（需要已安装依赖）
build-frontend:
	@pnpm --dir frontend run build

# 编译 datamanagementd（宿主机数据管理进程）
build-datamanagementd:
	@cd datamanagement && go build -o datamanagementd ./cmd/datamanagementd

# =============================================================================
# Test
# =============================================================================

# 运行测试（后端 + 前端）
test: test-backend test-frontend

test-backend:
	@$(MAKE) -C backend test

test-frontend:
	@pnpm --dir frontend run lint:check
	@pnpm --dir frontend run typecheck
	@$(MAKE) test-frontend-critical

test-frontend-critical:
	@pnpm --dir frontend exec vitest run $(FRONTEND_CRITICAL_VITEST)

test-datamanagementd:
	@cd datamanagement && go test ./...

secret-scan:
	@python3 tools/secret_scan.py

# =============================================================================
# Remote Deployment
# =============================================================================
# SSH_HOST  : SSH config alias for the server (default: racknerd-self)
# DEPLOY_DIR: docker-compose + .env directory on server (default: /root/sub2api)
# REPO_DIR  : source code directory on server for remote build (default: /root/sub2api-src)
#
# Typical workflow:
#   First time : make deploy-init   # create .env with random secrets
#   Code change: make deploy        # build locally + deploy
#   Config only: make deploy-sync   # push docker-compose/.env changes only
# =============================================================================

SSH_HOST   ?= racknerd-self
DEPLOY_DIR ?= /root/sub2api
REPO_DIR   ?= /root/sub2api-src

# 代码有修改时使用：本地构建前端 → 同步源码 → 服务器构建 Go → 重启容器
deploy:
	@echo ">>> [1/4] Building frontend locally ..."
	@pnpm --dir frontend install --frozen-lockfile
	@pnpm --dir frontend exec vite build
	@echo ">>> [2/4] Syncing source code to $(SSH_HOST):$(REPO_DIR) ..."
	@rsync -az --exclude='.git' --exclude='frontend/node_modules' --exclude='backend/vendor' \
	  --exclude='deploy/.env' --exclude='deploy/data/' --exclude='deploy/postgres_data/' --exclude='deploy/redis_data/' \
	  . $(SSH_HOST):$(REPO_DIR)/
	@echo ">>> [3/4] Syncing deploy configs to $(SSH_HOST):$(DEPLOY_DIR) ..."
	@ssh $(SSH_HOST) "mkdir -p $(DEPLOY_DIR) && rsync -a --exclude='.env' $(REPO_DIR)/deploy/ $(DEPLOY_DIR)/"
	@echo ">>> [4/4] Building image (Go only) and restarting services on $(SSH_HOST) ..."
	@ssh $(SSH_HOST) "cd $(REPO_DIR) && docker build -f Dockerfile.prebuilt -t sub2api:local . \
	  && docker compose -f $(DEPLOY_DIR)/docker-compose.yml up -d --pull never"
	@echo ">>> Deploy complete. Visit https://8k23h5ly.yagao.online"

# 仅同步 deploy/ 配置文件（不重建镜像，不重启）
deploy-sync:
	@echo ">>> Syncing deploy configs to $(SSH_HOST):$(DEPLOY_DIR) ..."
	@rsync -az --exclude='.env' --exclude='data/' --exclude='postgres_data/' --exclude='redis_data/' \
	  deploy/ $(SSH_HOST):$(DEPLOY_DIR)/

# 首次部署：在服务器上初始化 .env（自动生成随机密钥）
deploy-init:
	@echo ">>> Initializing $(SSH_HOST):$(DEPLOY_DIR) ..."
	@ssh $(SSH_HOST) "mkdir -p $(DEPLOY_DIR)"
	@ssh $(SSH_HOST) "[ -f $(DEPLOY_DIR)/.env ] && echo '.env already exists, skipping.' || \
	  (cd $(DEPLOY_DIR) && \
	   JWT_SECRET=\$$(openssl rand -hex 32) && \
	   TOTP_KEY=\$$(openssl rand -hex 32) && \
	   PG_PASS=\$$(openssl rand -hex 32) && \
	   cp .env.example .env && \
	   sed -i \"s/^JWT_SECRET=.*/JWT_SECRET=\$$JWT_SECRET/\" .env && \
	   sed -i \"s/^TOTP_ENCRYPTION_KEY=.*/TOTP_ENCRYPTION_KEY=\$$TOTP_KEY/\" .env && \
	   sed -i \"s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=\$$PG_PASS/\" .env && \
	   chmod 600 .env && echo '.env generated.')"

# 停止并移除容器（保留数据卷）
deploy-down:
	@ssh $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose down"

# 重启服务（不重建镜像）
deploy-restart:
	@ssh $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose up -d"

# 实时查看日志（Ctrl+C 退出）
deploy-logs:
	@ssh -t $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose logs -f --tail=100"

# 查看容器运行状态
deploy-status:
	@ssh $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose ps"

# 上传 Nginx 配置并重载
deploy-nginx:
	@scp deploy/nginx-sub2api.conf $(SSH_HOST):/etc/nginx/conf.d/sub2api.conf
	@ssh $(SSH_HOST) "nginx -t && systemctl reload nginx"
	@echo ">>> Nginx reloaded. Visit https://8k23h5ly.yagao.online"
