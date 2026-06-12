#!/bin/bash
# =============================================================================
# Sub2API 本地构建部署脚本
# 包含所有高危修改 + 管理员默认账号 + 安全默认值
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="$SCRIPT_DIR/.env"

# ── 生成 .env ──
echo "正在生成 .env 配置文件..."

cat > "$ENV_FILE" << 'ENVEOF'
# =============================================================================
# Sub2API 部署配置
# 安全默认值已启用，管理员账号已预配置
# =============================================================================

# ── 核心：管理员账号 ──
ADMIN_EMAIL=admin@shareCodex.local
ADMIN_PASSWORD=Sl990905xx

# ── 服务器 ──
SERVER_MODE=release
RUN_MODE=standard
SERVER_HOST=0.0.0.0
SERVER_PORT=8080
BIND_HOST=0.0.0.0

# ── 安全密钥（首次生成后请固定，不要每次重新生成） ──
JWT_SECRET=REPLACE_WITH_JWT_SECRET
TOTP_ENCRYPTION_KEY=REPLACE_WITH_TOTP_KEY

# ── 数据库 ──
POSTGRES_USER=sub2api
POSTGRES_PASSWORD=REPLACE_WITH_DB_PASSWORD
POSTGRES_DB=sub2api
DATABASE_MAX_OPEN_CONNS=50
DATABASE_MAX_IDLE_CONNS=10
DATABASE_CONN_MAX_LIFETIME_MINUTES=30
DATABASE_CONN_MAX_IDLE_TIME_MINUTES=5

# ── Redis ──
REDIS_PASSWORD=
REDIS_DB=0
REDIS_POOL_SIZE=1024
REDIS_MIN_IDLE_CONNS=10
REDIS_ENABLE_TLS=false

# ── 时区 ──
TZ=Asia/Shanghai

# ── 安全：URL 白名单（强制安全默认值） ──
SECURITY_URL_ALLOWLIST_ENABLED=false
SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP=false
SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS=false
SECURITY_URL_ALLOWLIST_UPSTREAM_HOSTS=

# ── Gemini OAuth（如需要请填入） ──
GEMINI_OAUTH_CLIENT_ID=
GEMINI_OAUTH_CLIENT_SECRET=
GEMINI_CLI_OAUTH_CLIENT_SECRET=

# ── Antigravity OAuth（如需要请填入） ──
ANTIGRAVITY_OAUTH_CLIENT_SECRET=
ANTIGRAVITY_USER_AGENT_VERSION=

# ── 日志 ──
LOG_LEVEL=info

# ── 网关 ──
GATEWAY_OPENAI_HTTP2_ENABLED=true
GATEWAY_IMAGE_CONCURRENCY_ENABLED=false

# ── 在线更新代理（国内服务器建议填写） ──
UPDATE_PROXY_URL=
ENVEOF

# ── 自动填充随机密钥 ──
if command -v openssl &>/dev/null; then
    JWT_SECRET=$(openssl rand -hex 32)
    TOTP_KEY=$(openssl rand -hex 32)
    DB_PASS=$(openssl rand -base64 32)
else
    JWT_SECRET=$(head -c 32 /dev/urandom | xxd -p | tr -d '\n')
    TOTP_KEY=$(head -c 32 /dev/urandom | xxd -p | tr -d '\n')
    DB_PASS=$(head -c 32 /dev/urandom | base64)
fi

sed -i.bak "s/REPLACE_WITH_JWT_SECRET/$JWT_SECRET/" "$ENV_FILE"
sed -i.bak "s/REPLACE_WITH_TOTP_KEY/$TOTP_KEY/" "$ENV_FILE"
sed -i.bak "s/REPLACE_WITH_DB_PASSWORD/$DB_PASS/" "$ENV_FILE"
rm -f "$ENV_FILE.bak"

echo "✅ .env 已生成：$ENV_FILE"

# ── 清理旧数据（如果存在已损坏的初始化状态） ──
read -p "是否清理旧容器和卷以重新初始化？(y/N): " RESET
if [[ "$RESET" =~ ^[Yy]$ ]]; then
    echo "停止并清理旧容器..."
    docker-compose down -v 2>/dev/null || true
    # 同时清理 standalone 模式的残留
    docker-compose -f docker-compose.standalone.yml down -v 2>/dev/null || true
fi

# ── 本地构建并启动 ──
echo ""
echo "正在本地构建 Docker 镜像（包含所有代码修改）..."
docker-compose build --no-cache

echo ""
echo "启动服务..."
docker-compose up -d

echo ""
echo "=============================================="
echo "🚀 部署完成！"
echo ""
echo "访问地址：http://localhost:8080"
echo ""
echo "管理员账号："
echo "  邮箱：admin@shareCodex.local"
echo "  密码：Sl990905xx"
echo ""
echo "安全密钥（已写入 .env）："
echo "  JWT_SECRET              = ${JWT_SECRET:0:16}..."
echo "  TOTP_ENCRYPTION_KEY     = ${TOTP_KEY:0:16}..."
echo "  POSTGRES_PASSWORD       = ${DB_PASS:0:16}..."
echo ""
echo "查看日志：docker-compose logs -f sub2api"
echo "=============================================="
