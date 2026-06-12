.PHONY: build build-backend build-frontend build-datamanagementd test test-backend test-frontend test-frontend-critical test-datamanagementd secret-scan \
        deploy deploy-init deploy-sync deploy-up deploy-down deploy-restart deploy-logs deploy-status deploy-pull deploy-nginx

# =============================================================================
# Deployment Configuration
# =============================================================================
SSH_HOST   ?= racknerd-self
DEPLOY_DIR ?= /root/sub2api
COMPOSE_FILE = docker-compose.yml

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
# Remote Deployment (SSH_HOST=racknerd-self, DEPLOY_DIR=/root/sub2api)
# =============================================================================

# 首次部署：在服务器建目录、同步配置、生成 .env、启动服务
deploy: deploy-sync deploy-up

# 在服务器上初始化目录并生成 .env（仅首次执行一次）
deploy-init:
	@echo ">>> Initializing $(SSH_HOST):$(DEPLOY_DIR) ..."
	@ssh $(SSH_HOST) "mkdir -p $(DEPLOY_DIR)"
	@ssh $(SSH_HOST) "[ -f $(DEPLOY_DIR)/.env ] && echo '.env already exists, skipping generation' || \
	  (cd $(DEPLOY_DIR) && \
	   JWT_SECRET=\$$(openssl rand -hex 32) && \
	   TOTP_KEY=\$$(openssl rand -hex 32) && \
	   PG_PASS=\$$(openssl rand -hex 32) && \
	   cp .env.example .env && \
	   sed -i \"s/^JWT_SECRET=.*/JWT_SECRET=\$$JWT_SECRET/\" .env && \
	   sed -i \"s/^TOTP_ENCRYPTION_KEY=.*/TOTP_ENCRYPTION_KEY=\$$TOTP_KEY/\" .env && \
	   sed -i \"s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=\$$PG_PASS/\" .env && \
	   chmod 600 .env && \
	   echo '.env generated successfully')"

# 将本地 deploy/ 目录（配置文件）同步到服务器（排除 .env 和数据目录）
deploy-sync:
	@echo ">>> Syncing deploy configs to $(SSH_HOST):$(DEPLOY_DIR) ..."
	@rsync -avz --exclude='.env' --exclude='data/' --exclude='postgres_data/' --exclude='redis_data/' \
	  deploy/ $(SSH_HOST):$(DEPLOY_DIR)/
	@echo ">>> Sync done. Run 'make deploy-init' if this is the first deployment."

# 在服务器上拉取最新镜像并启动/更新服务
deploy-up:
	@echo ">>> Pulling latest image and starting services on $(SSH_HOST) ..."
	@ssh $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose pull && docker compose up -d"

# 仅拉取最新镜像（不重启服务）
deploy-pull:
	@echo ">>> Pulling latest image on $(SSH_HOST) ..."
	@ssh $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose pull"

# 重启所有服务（拉取最新镜像）
deploy-restart:
	@echo ">>> Restarting services on $(SSH_HOST) ..."
	@ssh $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose pull && docker compose up -d"

# 停止并移除容器（保留数据卷）
deploy-down:
	@echo ">>> Stopping services on $(SSH_HOST) ..."
	@ssh $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose down"

# 查看远程日志（Ctrl+C 退出）
deploy-logs:
	@ssh -t $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose logs -f --tail=100"

# 查看服务运行状态
deploy-status:
	@ssh $(SSH_HOST) "cd $(DEPLOY_DIR) && docker compose ps"

# 上传 Nginx 配置并重载（需要服务器已有 Nginx）
deploy-nginx:
	@echo ">>> Uploading Nginx config to $(SSH_HOST) ..."
	@scp deploy/nginx-sub2api.conf $(SSH_HOST):/etc/nginx/conf.d/sub2api.conf
	@ssh $(SSH_HOST) "nginx -t && systemctl reload nginx"
	@echo ">>> Nginx reloaded. Visit https://8k23h5ly.yagao.online"
