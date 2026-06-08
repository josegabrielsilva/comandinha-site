#!/usr/bin/env bash
# Envia uma pasta local para public_html via FTPS (21) ou SFTP (22) no HostGator.
set -euo pipefail

LOCAL_DIR="${1:?Informe a pasta local (ex: dist)}"
: "${FTP_HOST:?Defina FTP_HOST}"
: "${FTP_USER:?Defina FTP_USER}"
: "${FTP_PASSWORD:?Defina FTP_PASSWORD}"

FTP_PORT="${FTP_PORT:-21}"
# Conta FTP do cPanel com diretório = public_html já entra na raiz do site (use ".").
# Conta principal (home) precisa de "public_html".
FTP_REMOTE_DIR="${FTP_REMOTE_DIR:-.}"
FTP_REMOTE_DIR="${FTP_REMOTE_DIR#/}"
[[ -z "$FTP_REMOTE_DIR" ]] && FTP_REMOTE_DIR="."

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

LFTP_BATCH="$(mktemp)"
cleanup() { rm -f "$LFTP_BATCH"; }
trap cleanup EXIT
chmod 600 "$LFTP_BATCH"

lftp_quote() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
FTP_USER_ESC="$(lftp_quote "$FTP_USER")"
FTP_PASSWORD_ESC="$(lftp_quote "$FTP_PASSWORD")"

echo "${FTP_MODE} → ${FTP_USER}@${FTP_HOST}:${FTP_PORT}/${FTP_REMOTE_DIR}"

write_lftp_batch() {
  local open_url="$1"
  {
    printf '%s\n' "set net:timeout 30"
    printf '%s\n' "set net:max-retries 2"
    printf '%s\n' "set ssl:verify-certificate no"
    if [[ "$FTP_SCHEME" == "ftps" ]]; then
      # Porta 21 = FTPS explícito (AUTH TLS). ftps:// força TLS implícito e quebra o handshake.
      printf '%s\n' "set ftp:ssl-force true"
      printf '%s\n' "set ftp:ssl-protect-data true"
      printf '%s\n' "set ftp:ssl-auth TLS"
    else
      printf '%s\n' "set sftp:auto-confirm yes"
    fi
    printf '%s\n' "open -u '${FTP_USER_ESC}','${FTP_PASSWORD_ESC}' ${open_url}"
    printf '%s\n' "lcd ${LOCAL_DIR}"
    if [[ "$FTP_REMOTE_DIR" != "." ]]; then
      printf '%s\n' "set cmd:fail-exit false"
      printf '%s\n' "cd ${FTP_REMOTE_DIR}"
      printf '%s\n' "set cmd:fail-exit true"
    fi
    printf '%s\n' "pwd"
    printf '%s\n' "mirror -R --delete --verbose --exclude-glob .DS_Store"
    printf '%s\n' "bye"
  } >"$LFTP_BATCH"
}

if [[ "$FTP_SCHEME" == "ftps" ]]; then
  write_lftp_batch "ftp://${FTP_HOST}:${FTP_PORT}"
else
  write_lftp_batch "sftp://${FTP_HOST}:${FTP_PORT}"
fi

lftp -f "$LFTP_BATCH"
