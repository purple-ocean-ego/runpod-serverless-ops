#!/usr/bin/env bash
set -euo pipefail

# Configure GitHub SSH key from RunPod secrets.
# Supported env vars:
# - GITHUB_SSH_KEY:     raw private key text (BEGIN/END included)
# - GITHUB_SSH_KEY_B64: base64-encoded private key text
#
# Optional env vars:
# - GITHUB_SSH_KEY_PATH: destination key path (default: ~/.ssh/id_ed25519_github)
# - GITHUB_SSH_HOST:     host name in ssh config (default: github.com)

KEY_PATH="${GITHUB_SSH_KEY_PATH:-$HOME/.ssh/id_ed25519_github}"
SSH_HOST="${GITHUB_SSH_HOST:-github.com}"
SSH_DIR="$(dirname "$KEY_PATH")"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ -n "${GITHUB_SSH_KEY_B64:-}" ]]; then
  printf '%s' "$GITHUB_SSH_KEY_B64" | base64 -d > "$KEY_PATH"
elif [[ -n "${GITHUB_SSH_KEY:-}" ]]; then
  # Keep line breaks as-is to preserve key format.
  printf '%s\n' "$GITHUB_SSH_KEY" > "$KEY_PATH"
else
  echo "setup_github_ssh: skip (GITHUB_SSH_KEY or GITHUB_SSH_KEY_B64 is not set)"
  exit 0
fi

chmod 600 "$KEY_PATH"

KNOWN_HOSTS="$SSH_DIR/known_hosts"
touch "$KNOWN_HOSTS"
chmod 644 "$KNOWN_HOSTS"
if ! grep -q "github\\.com" "$KNOWN_HOSTS"; then
  ssh-keyscan github.com >> "$KNOWN_HOSTS" 2>/dev/null || true
fi

SSH_CONFIG="$SSH_DIR/config"

# 自分の設定がまだ書き込まれていない場合のみ実行（二重追記の防止）
if ! grep -q "IdentityFile ${KEY_PATH}" "$SSH_CONFIG" 2>/dev/null; then

  # 一時ファイルを作成して、自分の設定を最初に書く
  TMP_CONFIG=$(mktemp)
  cat > "$TMP_CONFIG" <<EOF
Host ${SSH_HOST}
  HostName github.com
  User git
  IdentityFile ${KEY_PATH}
  IdentitiesOnly yes

EOF

  # 既存のconfigがあれば、その後ろに連結する
  if [[ -f "$SSH_CONFIG" ]]; then
    cat "$SSH_CONFIG" >> "$TMP_CONFIG"
  fi

  # 元の場所に書き戻す
  mv "$TMP_CONFIG" "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"

fi

echo "setup_github_ssh: configured key at ${KEY_PATH}"
