#!/usr/bin/env bash
# Envia uma pasta local para public_html via FTPS (21) ou SFTP (22) no HostGator.
set -euo pipefail

LOCAL_DIR="${1:?Informe a pasta local (ex: dist)}"
: "${FTP_HOST:?Defina FTP_HOST}"
: "${FTP_USER:?Defina FTP_USER}"
: "${FTP_PASSWORD:?Defina FTP_PASSWORD}"

FTP_PORT="${FTP_PORT:-21}"
FTP_REMOTE_DIR="${FTP_REMOTE_DIR:-public_html}"

FTP_HOST="$(printf '%s' "$FTP_HOST" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
FTP_USER="$(printf '%s' "$FTP_USER" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
FTP_PASSWORD="$(printf '%s' "$FTP_PASSWORD" | tr -d '\r\n')"

if [[ ! -d "$LOCAL_DIR" ]]; then
  echo "Pasta local não encontrada: $LOCAL_DIR" >&2
  exit 1
fi

if [[ "$FTP_HOST" == *usecomandinha.com.br* ]]; then
  echo "AVISO: FTP_HOST aponta para o domínio ($FTP_HOST)." >&2
  echo "No CI, use o hostname do servidor no cPanel (ex: br1234.hostgator.com.br)." >&2
fi

if ! command -v lftp >/dev/null 2>&1; then
  echo "Instale o lftp: brew install lftp" >&2
  exit 1
fi

if [[ "$FTP_PORT" == "21" ]]; then
  FTP_SCHEME="ftps"
  FTP_MODE="FTPS"
else
  FTP_SCHEME="sftp"
  FTP_MODE="SFTP"
fi

NETRC="${HOME}/.netrc"
cleanup() { rm -f "$NETRC"; }
trap cleanup EXIT

umask 077
{
  printf 'machine %s\n' "$FTP_HOST"
  printf 'login %s\n' "$FTP_USER"
  printf 'password %s\n' "$FTP_PASSWORD"
} >"$NETRC"

echo "${FTP_MODE} → ${FTP_USER}@${FTP_HOST}:${FTP_PORT}/${FTP_REMOTE_DIR}"

if [[ "$FTP_SCHEME" == "ftps" ]]; then
  # Porta 21 = FTPS explícito (AUTH TLS). ftps:// força TLS implícito e quebra o handshake.
  lftp -e "
set ftp:ssl-force true
set ftp:ssl-protect-data true
set ftp:ssl-auth TLS
set ssl:verify-certificate no
set net:timeout 30
set net:max-retries 2
open ftp://${FTP_HOST}:${FTP_PORT}
lcd ${LOCAL_DIR}
cd ${FTP_REMOTE_DIR}
mirror -R --delete --verbose --exclude-glob .DS_Store
bye
"
else
  lftp -e "
set sftp:auto-confirm yes
set ssl:verify-certificate no
set net:timeout 30
set net:max-retries 2
open sftp://${FTP_HOST}:${FTP_PORT}
lcd ${LOCAL_DIR}
cd ${FTP_REMOTE_DIR}
mirror -R --delete --verbose --exclude-glob .DS_Store
bye
"
fi
