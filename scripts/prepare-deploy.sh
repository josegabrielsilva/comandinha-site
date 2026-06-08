#!/usr/bin/env bash
# Monta a pasta dist/ com só o que vai para public_html no HostGator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/dist}"

rm -rf "$DEST"
mkdir -p "$DEST"

cp "$ROOT/index.html" "$ROOT/privacidade.html" "$ROOT/termos.html" "$ROOT/.htaccess" "$DEST/"
cp -R "$ROOT/css" "$ROOT/js" "$ROOT/assets" "$DEST/"

# Limpa lixo de macOS se existir
find "$DEST" -name '.DS_Store' -delete 2>/dev/null || true

echo "Deploy bundle pronto em: $DEST"
