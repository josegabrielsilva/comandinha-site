#!/usr/bin/env bash
# Sobe dist/ para public_html no HostGator via SFTP (porta 22).
# Credenciais: copie .env.deploy.example → .env.deploy e preencha.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${DEPLOY_ENV:-$ROOT/.env.deploy}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a
fi

: "${FTP_HOST:?Defina FTP_HOST (hostname do servidor no cPanel, NÃO o domínio)}"
: "${FTP_USER:?Defina FTP_USER (usuário FTP do cPanel)}"
: "${FTP_PASSWORD:?Defina FTP_PASSWORD}"
FTP_PORT="${FTP_PORT:-22}"
FTP_REMOTE_DIR="${FTP_REMOTE_DIR:-public_html}"

"$ROOT/scripts/prepare-deploy.sh" "$ROOT/dist"

if ! command -v lftp >/dev/null 2>&1; then
  echo "Instale o lftp: brew install lftp" >&2
  exit 1
fi

echo "Enviando via SFTP para $FTP_HOST:$FTP_PORT/$FTP_REMOTE_DIR ..."

lftp -e "
set sftp:auto-confirm yes
set ssl:verify-certificate no
open -u $FTP_USER,$FTP_PASSWORD sftp://$FTP_HOST:$FTP_PORT
lcd $ROOT/dist
cd $FTP_REMOTE_DIR
mirror -R --delete --verbose --exclude-glob .DS_Store
bye
"

if [[ -n "${CLOUDFLARE_ZONE_ID:-}" && -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "Limpando cache do Cloudflare..."
  curl -fsS -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{"purge_everything":true}' >/dev/null
  echo "Cache do Cloudflare purgado."
fi

echo "Deploy concluído: https://usecomandinha.com.br"
