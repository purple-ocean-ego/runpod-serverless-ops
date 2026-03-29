#!/bin/bash

# runpod_s3 スキルのエントリポイント
# uv (ポータブルなPythonパッケージマネージャー) を使って
# インストール不要で boto3 を実行します。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
BIN_DIR="$SKILL_DIR/bin"
UV_BIN="$BIN_DIR/uv"
PY_SCRIPT="$SCRIPT_DIR/runpod_s3.py"
ENV_FILE="$SKILL_DIR/.env"

# 1. .env の存在チェック (スキルを自己完結させるため)
if [ ! -f "$ENV_FILE" ]; then
    echo "エラー: $ENV_FILE が見つかりません。" >&2
    echo "  .agents/skills/runpod_s3/.env.example をコピーして .env を作成してください。" >&2
    exit 1
fi

# 2. uv バイナリがなければ自動ダウンロード（システムへのインストール不要）
if [ ! -f "$UV_BIN" ]; then
    echo "uv が見つかりません。ダウンロードを開始します..."
    mkdir -p "$BIN_DIR"
    TMP_ARCHIVE="$(mktemp /tmp/uv-XXXXXX.tar.gz)"
    curl -sSL "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-unknown-linux-musl.tar.gz" \
        -o "$TMP_ARCHIVE"
    tar -xzf "$TMP_ARCHIVE" -C "$BIN_DIR" --strip-components=1 uv-x86_64-unknown-linux-musl/uv
    rm -f "$TMP_ARCHIVE"
    chmod +x "$UV_BIN"
    echo "uv のダウンロードが完了しました。"
fi

# 2. Python スクリプトの存在確認
if [ ! -f "$PY_SCRIPT" ]; then
    echo "エラー: $PY_SCRIPT が見つかりません。" >&2
    exit 1
fi

# 3. uv を使って boto3 をインストールせずにスクリプトを実行
#    --with boto3: 実行時のみ一時的にライブラリを読み込む（システムを汚さない）
exec "$UV_BIN" run --quiet --with boto3 "$PY_SCRIPT" "$@"
