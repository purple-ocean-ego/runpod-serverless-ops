#!/bin/bash

# ==============================================================================
# ComfyUI ローカル開発環境 初期化スクリプト
# ==============================================================================
# コンテナ起動時に実行される。ComfyUI本体のclone、依存解決、起動を行う。

set -e

COMFYUI_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="/workspace/custom_nodes"
OUTPUT_DIR="/workspace/output"
INPUT_DIR="/workspace/input"
MODEL_PATHS_CONFIG="/workspace/extra_model_paths.yaml"

# uv のグローバル設定
export UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu126"
export UV_LINK_MODE=copy
export UV_BREAK_SYSTEM_PACKAGES=1

echo "===================================================================="
echo "  🚀 ComfyUI Local Dev Environment - Setup Starting"
echo "===================================================================="

# -------------------------------------------------------------
# 1. ComfyUI 本体のインストール
# -------------------------------------------------------------
git config --global --add safe.directory "*"
if [ ! -d "$COMFYUI_DIR/.git" ]; then
    echo "📦 Cloning ComfyUI..."
    # マウントにより空ディレクトリが既に存在するため、中に直接 clone する
    cd "$COMFYUI_DIR"
    git init
    git remote add origin https://github.com/comfy-org/ComfyUI.git
    git fetch origin
    git checkout -b master origin/master
    cd /workspace
else
    echo "✅ ComfyUI already exists. Skipping clone."
    echo "   (手動で git pull を実行してください)"
fi

# ComfyUI の requirements.txt を実行（焼き込み済みのため差分のみインストール）
echo "📦 Syncing ComfyUI requirements..."
uv pip install --system --no-cache-dir -r "$COMFYUI_DIR/requirements.txt" 2>/dev/null || true

# -------------------------------------------------------------
# 2. カスタムノードのシンボリックリンク
# -------------------------------------------------------------
echo "🔗 Setting up custom_nodes symlink..."
if [ -d "$COMFYUI_DIR/custom_nodes" ] && [ ! -L "$COMFYUI_DIR/custom_nodes" ]; then
    # ComfyUI が持っているデフォルトの custom_nodes を外部化
    cp -n -r "$COMFYUI_DIR/custom_nodes/"* "$CUSTOM_NODES_DIR/" 2>/dev/null || true
    rm -rf "$COMFYUI_DIR/custom_nodes"
    ln -s "$CUSTOM_NODES_DIR" "$COMFYUI_DIR/custom_nodes"
elif [ ! -e "$COMFYUI_DIR/custom_nodes" ]; then
    ln -s "$CUSTOM_NODES_DIR" "$COMFYUI_DIR/custom_nodes"
fi
echo "✅ custom_nodes → $CUSTOM_NODES_DIR"

# -------------------------------------------------------------
# 3. カスタムノードの依存関係を自動インストール
# -------------------------------------------------------------
if [ -d "$CUSTOM_NODES_DIR" ]; then
    NODE_COUNT=$(find "$CUSTOM_NODES_DIR" -maxdepth 2 -name "requirements.txt" | wc -l)
    if [ "$NODE_COUNT" -gt 0 ]; then
        echo "📦 Installing dependencies for $NODE_COUNT custom node(s)..."
        # FD 3 を使用して、ループ内の uv が入力を消費するのを防止
        find "$CUSTOM_NODES_DIR" -maxdepth 2 -name "requirements.txt" | while read -r -u 3 req_file; do
            echo "   📦 $(dirname "$req_file" | xargs basename): $req_file"
            uv pip install --system --no-cache-dir -r "$req_file" 2>/dev/null || \
                echo "   ⚠️  Failed: $req_file (continuing...)"
        done 3<&0
        echo "✅ Custom node dependencies installed."
    else
        echo "ℹ️  No custom nodes found."
    fi
fi

# -------------------------------------------------------------
# 4. ComfyUI 起動
# -------------------------------------------------------------
echo "===================================================================="
echo "  🎨 Starting ComfyUI (--lowvram mode for GTX 1660)"
echo "===================================================================="

cd "$COMFYUI_DIR"
exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --output-directory "$OUTPUT_DIR" \
    --input-directory "$INPUT_DIR" \
    --extra-model-paths-config "$MODEL_PATHS_CONFIG" \
    --lowvram
