#!/bin/bash

# ==============================================================================
# ComfyUI ポッド起動スクリプト (モジュール化版)
# ==============================================================================

# 自ディレクトリの取得 (外部ファイル読み込み用)
SCRIPT_DIR=$(cd $(dirname $0); pwd)

# ユーティリティの読み込み
source "${SCRIPT_DIR}/setup_utils.sh"
source "${SCRIPT_DIR}/comfy_runner.sh"

# 引数解析 (デフォルト: --highvram)
VRAM_FLAG="--highvram"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --lowvram) VRAM_FLAG="--lowvram" ;;
    esac
    shift
done

# ==============================================================================
# メイン実行セクション
# ==============================================================================

# 1. 前準備
prepare_directories
# デバッグ用：venv のパッケージリストを保存
uv pip list > /runpod-volume/venv_pip_list.txt 2>/dev/null || true


prepare_venv

install_llama_cpp

install_comfyui
externalize_custom_nodes

install_manager_requirements

# 2. 起動フロー
cd /runpod-volume/ComfyUI
start_comfyui "$VRAM_FLAG"
wait_for_comfyui

# 3. 設定適用 (初回起動後に config.ini が作られるのを待ってから適用)
apply_manager_settings_and_restart "$VRAM_FLAG"

echo "ComfyUI is now ready and accessible on port 8188!"
