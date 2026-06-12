#!/bin/bash
# =============================================================================
# Sub2API .env 安全生成脚本
# 使用说明：
#   cd deploy
#   chmod +x generate-env.sh
#   ./generate-env.sh
# =============================================================================

set -euo pipefail

ENV_FILE=".env"

# 如果 .env 已存在，先备份
if [[ -f "$ENV_FILE" ]]; then
    BACKUP="$ENV_FILE.$(date +%Y%m%d%H%M%S).bak"
    cp "$ENV_FILE" "$BACKUP"
    echo "已备份现有 .env 到 $BACKUP"
fi

# 从 .env.example 复制模板
cp .env.example "$ENV_FILE"

echo "正在生成安全配置..."

# 生成核心安全密钥
JWT_SECRET=$(openssl rand -hex 32)
TOTP_ENCRYPTION_KEY=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -base64 32)

# 生成方法说明：sed -i '' 用于 macOS，sed -i 用于 Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_INPLACE="sed -i ''"
else
    SED_INPLACE="sed -i"
fi

# 替换核心密钥
$SED_INPLACE "s/^JWT_SECRET=.*/JWT_SECRET=${JWT_SECRET}/" "$ENV_FILE"
$SED_INPLACE "s/^TOTP_ENCRYPTION_KEY=.*/TOTP_ENCRYPTION_KEY=${TOTP_ENCRYPTION_KEY}/" "$ENV_FILE"
$SED_INPLACE "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" "$ENV_FILE"

# 强制 release 模式
$SED_INPLACE "s/^SERVER_MODE=.*/SERVER_MODE=release/" "$ENV_FILE"

# 安全默认值（已在 example 中设置，双重确认）
$SED_INPLACE "s/^SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP=.*/SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP=false/" "$ENV_FILE"
$SED_INPLACE "s/^SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS=.*/SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS=false/" "$ENV_FILE"

# 日志级别
$SED_INPLACE "s/^LOG_LEVEL=.*/LOG_LEVEL=info/" "$ENV_FILE"

echo ""
echo "=============================================="
echo ".env 文件已生成：$(pwd)/$ENV_FILE"
echo ""
echo "核心密钥已自动填充："
echo "  JWT_SECRET              = ${JWT_SECRET}"
echo "  TOTP_ENCRYPTION_KEY     = ${TOTP_ENCRYPTION_KEY}"
echo "  POSTGRES_PASSWORD       = ${POSTGRES_PASSWORD}"
echo ""
echo "⚠️  请手动修改以下配置："
echo "  BASE_URL                = https://你的域名.com"
echo "  FRONTEND_URL            = https://你的域名.com"
echo ""
echo "📝 如果使用 Codex Plus OAuth 入池，还需配置："
echo "  # 不需要额外 OAuth Secret（OpenAI OAuth 使用 PKCE，已内置 client_id）"
echo ""
echo "📝 如果使用 Gemini CLI 功能，需配置："
echo "  GEMINI_CLI_OAUTH_CLIENT_SECRET=你的值"
echo ""
echo "📝 如果使用 Antigravity 功能，需配置："
echo "  ANTIGRAVITY_OAUTH_CLIENT_SECRET=你的值"
echo ""
echo "⚠️  管理员密码已在 config.yaml 中配置："
echo "  admin_email             = admin@shareCodex.local"
echo "  admin_password          = （已配置）"
echo "=============================================="
