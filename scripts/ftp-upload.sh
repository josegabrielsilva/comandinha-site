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

FTP_SITE_DOMAIN=""
if [[ "$FTP_USER" == *"@"* ]]; then
  FTP_SITE_DOMAIN="${FTP_USER#*@}"
fi

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

extract_remote_listing() {
  awk '
    BEGIN { after_pwd = 0 }
    /^ftp:\/\// {
      if (after_pwd) exit
      after_pwd = 1
      next
    }
    after_pwd && /^cd: / { exit }
    after_pwd && /^ls: / { exit }
    after_pwd && /^get: / { exit }
    after_pwd && /^mirror: / { exit }
    after_pwd { print }
  ' <<<"$1"
}

remote_listing_has() {
  local name="$1"
  local listing="$2"
  printf '%s\n' "$listing" | grep -Fxq "$name"
}

cd_to_path_failed() {
  local path="$1"
  local log="$2"
  printf '%s\n' "$log" | grep -Fq "cd: Access failed: 550 Can't change directory to /${path}"
}

listing_looks_like_cpanel_home() {
  local listing="$1"
  remote_listing_has "$FTP_REMOTE_DIR" "$listing" \
    || remote_listing_has "mail" "$listing" \
    || remote_listing_has "etc" "$listing" \
    || remote_listing_has "logs" "$listing" \
    || remote_listing_has "tmp" "$listing"
}

build_remote_candidates() {
  REMOTE_CANDIDATES=("$FTP_REMOTE_DIR")
  if [[ -n "$FTP_SITE_DOMAIN" ]]; then
    REMOTE_CANDIDATES+=("../${FTP_REMOTE_DIR}")
    REMOTE_CANDIDATES+=("../../${FTP_REMOTE_DIR}")
    REMOTE_CANDIDATES+=("${FTP_SITE_DOMAIN}/${FTP_REMOTE_DIR}")
    REMOTE_CANDIDATES+=("domains/${FTP_SITE_DOMAIN}/${FTP_REMOTE_DIR}")
  fi
}

resolve_mirror_target() {
  local pwd_start="$1"
  local pwd_end="$2"
  local listing="$3"
  local probe_log="$4"
  local candidate resolved=""

  # Entrou em public_html com sucesso.
  if [[ "$pwd_end" == *"${FTP_REMOTE_DIR}"* && "$pwd_end" != "$pwd_start" ]]; then
    RESOLVED_MIRROR_TARGET="."
    RESOLVED_MIRROR_LABEL="$pwd_end"
    return 0
  fi

  # Conta principal: abre na home do cPanel e public_html é subpasta visível.
  if [[ "$pwd_start" == *"/home"* ]] || listing_looks_like_cpanel_home "$listing"; then
    if remote_listing_has "$FTP_REMOTE_DIR" "$listing" \
      || [[ "$pwd_start" == *"/home"* ]]; then
      RESOLVED_MIRROR_TARGET="$FTP_REMOTE_DIR"
      RESOLVED_MIRROR_LABEL="${pwd_start%/}/${FTP_REMOTE_DIR}"
      return 0
    fi
  fi

  build_remote_candidates
  for candidate in "${REMOTE_CANDIDATES[@]}"; do
    if ! cd_to_path_failed "$candidate" "$probe_log"; then
      if [[ "$candidate" == "$FTP_REMOTE_DIR" ]]; then
        RESOLVED_MIRROR_TARGET="."
        RESOLVED_MIRROR_LABEL="$pwd_end"
      else
        RESOLVED_MIRROR_TARGET="$candidate"
        RESOLVED_MIRROR_LABEL="${pwd_start%/}/${candidate}"
      fi
      return 0
    fi
    if remote_listing_has "${candidate%%/*}" "$listing"; then
      resolved="$candidate"
    fi
  done

  if [[ -n "$resolved" ]]; then
    RESOLVED_MIRROR_TARGET="$resolved"
    RESOLVED_MIRROR_LABEL="${pwd_start%/}/${resolved}"
    return 0
  fi

  if remote_listing_has "$FTP_REMOTE_DIR" "$listing"; then
    RESOLVED_MIRROR_TARGET="$FTP_REMOTE_DIR"
    RESOLVED_MIRROR_LABEL="${pwd_start%/}/${FTP_REMOTE_DIR}"
    return 0
  fi

  # Chroot em public_html: login em /, sem subpasta public_html, cd falha.
  if [[ "${FTP_ASSUME_CHROOT_PUBLIC_HTML:-}" == "1" || "${FTP_ASSUME_CHROOT_PUBLIC_HTML:-}" == "true" ]]; then
    RESOLVED_MIRROR_TARGET="."
    RESOLVED_MIRROR_LABEL="${pwd_start} (chroot em ${FTP_REMOTE_DIR})"
    return 0
  fi

  return 1
}

# Descobre o destino remoto: lista o diretório e testa caminhos típicos do HostGator.
{
  write_lftp_open "$(open_url)"
  printf '%s\n' "pwd"
  printf '%s\n' "cls -1"
  build_remote_candidates
  for candidate in "${REMOTE_CANDIDATES[@]}"; do
    printf '%s\n' "set cmd:fail-exit false"
    printf '%s\n' "cd ${candidate}"
    printf '%s\n' "pwd"
  done
  printf '%s\n' "bye"
} >"$LFTP_BATCH"

PROBE_LOG="$(lftp -f "$LFTP_BATCH" 2>&1 | tee /dev/stderr)"
PWD_LINES="$(extract_pwd_lines "$PROBE_LOG")"
PWD_START="$(printf '%s\n' "$PWD_LINES" | sed -n '1p')"
PWD_END="$(printf '%s\n' "$PWD_LINES" | tail -n 1)"
REMOTE_LISTING="$(extract_remote_listing "$PROBE_LOG")"

if [[ -z "$PWD_START" ]]; then
  echo "ERRO: não foi possível ler o diretório remoto após o login FTP." >&2
  exit 1
fi

if ! resolve_mirror_target "$PWD_START" "$PWD_END" "$REMOTE_LISTING" "$PROBE_LOG"; then
  echo "ERRO: a conta FTP não alcança ${FTP_REMOTE_DIR}." >&2
  echo "Login: ${PWD_START}" >&2
  if [[ -n "$REMOTE_LISTING" ]]; then
    echo "Conteúdo visível após o login:" >&2
    printf '%s\n' "$REMOTE_LISTING" | sed 's/^/  /' >&2
  fi
  echo "" >&2
  echo "A conta (${FTP_USER}) parece presa em outro diretório (ex.: usecomandinha.com.br/github)." >&2
  echo "O site público fica em /home/.../public_html — não dentro de github/." >&2
  echo "" >&2
  echo "Corrija no cPanel → Contas de FTP → ${FTP_USER}:" >&2
  echo "  Diretório = public_html   (caminho: /home1/SEU_USUARIO/public_html)" >&2
  echo "" >&2
  echo "Alternativa: use o usuário FTP principal do cPanel (abre na home e enxerga public_html/)." >&2
  echo "Depois de apontar a conta para public_html, defina FTP_ASSUME_CHROOT_PUBLIC_HTML=true no CI." >&2
  exit 1
fi

echo "Destino remoto: ${RESOLVED_MIRROR_LABEL}"

{
  write_lftp_open "$(open_url)"
  printf '%s\n' "lcd ${LOCAL_DIR}"
  if [[ "$RESOLVED_MIRROR_TARGET" == "." ]]; then
    printf '%s\n' "mirror -R --delete --overwrite --verbose --exclude-glob .DS_Store . ."
  else
    printf '%s\n' "mirror -R --delete --overwrite --verbose --exclude-glob .DS_Store . ${RESOLVED_MIRROR_TARGET}/"
  fi
  printf '%s\n' "bye"
} >"$LFTP_BATCH"

lftp -f "$LFTP_BATCH"
