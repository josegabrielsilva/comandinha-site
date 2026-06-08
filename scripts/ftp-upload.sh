#!/usr/bin/env bash
# Envia uma pasta local para public_html via FTPS (21) ou SFTP (22) no HostGator.
set -euo pipefail

LOCAL_DIR="${1:?Informe a pasta local (ex: dist)}"
: "${FTP_HOST:?Defina FTP_HOST}"
: "${FTP_USER:?Defina FTP_USER}"
: "${FTP_PASSWORD:?Defina FTP_PASSWORD}"

FTP_PORT="${FTP_PORT:-21}"
FTP_REMOTE_DIR="${FTP_REMOTE_DIR:-public_html}"
FTP_REMOTE_DIR="${FTP_REMOTE_DIR#/}"
[[ -z "$FTP_REMOTE_DIR" || "$FTP_REMOTE_DIR" == "." ]] && FTP_REMOTE_DIR="public_html"

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

write_lftp_open_settings() {
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
}

write_lftp_open() {
  local open_url="$1"
  write_lftp_open_settings
  printf '%s\n' "open -u '${FTP_USER_ESC}','${FTP_PASSWORD_ESC}' ${open_url}"
}

open_url() {
  if [[ "$FTP_SCHEME" == "ftps" ]]; then
    printf 'ftp://%s:%s' "$FTP_HOST" "$FTP_PORT"
  else
    printf 'sftp://%s:%s' "$FTP_HOST" "$FTP_PORT"
  fi
}

extract_pwd_lines() {
  printf '%s\n' "$1" | grep -E '^ftp://' || true
}

# Descobre se precisamos entrar em public_html ou enviar para public_html/ a partir da home.
{
  write_lftp_open "$(open_url)"
  printf '%s\n' "pwd"
  printf '%s\n' "set cmd:fail-exit false"
  printf '%s\n' "cd ${FTP_REMOTE_DIR}"
  printf '%s\n' "set cmd:fail-exit true"
  printf '%s\n' "pwd"
  printf '%s\n' "bye"
} >"$LFTP_BATCH"

PROBE_LOG="$(lftp -f "$LFTP_BATCH" 2>&1 | tee /dev/stderr)"
PWD_LINES="$(extract_pwd_lines "$PROBE_LOG")"
PWD_START="$(printf '%s\n' "$PWD_LINES" | sed -n '1p')"
PWD_END="$(printf '%s\n' "$PWD_LINES" | sed -n '2p')"

if [[ -z "$PWD_START" || -z "$PWD_END" ]]; then
  echo "ERRO: não foi possível ler o diretório remoto após o login FTP." >&2
  exit 1
fi

MIRROR_TARGET="."
if [[ "$PWD_END" == *"${FTP_REMOTE_DIR}"* ]]; then
  MIRROR_TARGET="."
elif [[ "$PWD_START" == *"/home"* && "$PWD_START" == "$PWD_END" ]]; then
  # Conta principal do cPanel: FTP abre em /home1/usuario e o cd pode falhar no lftp.
  MIRROR_TARGET="${FTP_REMOTE_DIR}"
elif [[ "$PWD_START" != *"/home"* ]]; then
  # Conta FTP já presa em public_html (chroot).
  MIRROR_TARGET="."
else
  echo "ERRO: não foi possível resolver o destino remoto." >&2
  echo "Início: ${PWD_START}" >&2
  echo "Fim:    ${PWD_END}" >&2
  exit 1
fi

if [[ "$MIRROR_TARGET" == "${FTP_REMOTE_DIR}" ]]; then
  echo "Destino remoto: ${PWD_START}/${FTP_REMOTE_DIR}"
else
  echo "Destino remoto confirmado: ${PWD_END}"
fi

{
  write_lftp_open "$(open_url)"
  printf '%s\n' "lcd ${LOCAL_DIR}"
  if [[ "$MIRROR_TARGET" == "${FTP_REMOTE_DIR}" ]]; then
    printf '%s\n' "mirror -R --delete --overwrite --verbose --exclude-glob .DS_Store . ${FTP_REMOTE_DIR}/"
  else
    printf '%s\n' "set cmd:fail-exit false"
    printf '%s\n' "cd ${FTP_REMOTE_DIR}"
    printf '%s\n' "set cmd:fail-exit true"
    printf '%s\n' "mirror -R --delete --overwrite --verbose --exclude-glob .DS_Store . ."
  fi
  printf '%s\n' "bye"
} >"$LFTP_BATCH"

lftp -f "$LFTP_BATCH"
