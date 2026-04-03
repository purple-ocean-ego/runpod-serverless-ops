#!/bin/bash

# ==============================================================================
# ComfyUI ポッド起動スクリプト (モジュール化版)
# ==============================================================================

# 自ディレクトリの取得 (外部ファイル読み込み用)
SCRIPT_DIR=$(cd $(dirname $0); pwd)

# ユーティリティの読み込み
source "${SCRIPT_DIR}/setup_utils.sh"
source "${SCRIPT_DIR}/comfy_runner.sh"

# ==============================================================================
# メイン実行セクション
# ==============================================================================

# 1. 前準備
prepare_directories
# デバッグ用：ベースイメージのパッケージリストを保存
/usr/bin/pip list > /runpod-volume/base_pip_list.txt

prepare_venv

install_comfyui
check_pytorch_health
externalize_custom_nodes

install_manager_requirements

# 2. 起動フロー
cd /runpod-volume/ComfyUI
start_comfyui
wait_for_comfyui

# 3. 設定適用 (初回起動後に config.ini が作られるのを待ってから適用)
apply_manager_settings_and_restart

echo "ComfyUI is now ready and accessible on port 8188!"
