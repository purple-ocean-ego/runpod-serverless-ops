#!/bin/bash

# ==============================================================================
# RunPod Serverless起動スクリプト (モジュール化版)
# ==============================================================================

# 自ディレクトリの取得 (外部ファイル読み込み用)
SCRIPT_DIR=$(cd $(dirname $0); pwd)

# ユーティリティの読み込み
source "${SCRIPT_DIR}/setup_utils.sh"

LOCK_FILE="/runpod-volume/setup.lock"

echo "Acquiring lock for setup..."
(
    flock -x 200

    echo "Lock acquired. Proceeding with setup..."

    # 共通関数によるセットアップ
    prepare_directories
    prepare_venv
    
    # Serverlessハンドラ用追加ライブラリ（インストール済みならスキップして venv 競合を回避）
    if ! python -c "import runpod, requests" 2>/dev/null; then
        echo "Installing missing handler dependencies with uv..."
        uv pip install --no-cache-dir -q runpod requests
    fi


    # 本体のインストールとカスタムノードの外部化
    install_comfyui
    check_pytorch_health
    externalize_custom_nodes


    echo "Setup finished. Releasing lock..."
) 200>"$LOCK_FILE"


# 仮想環境を確実に有効化する
source /runpod-volume/venv/bin/activate

# ComfyUIの本体起動は、最初のリクエストが来た時にハンドラー側で行う
# これによりコンテナ起動時のリソース競合（25秒即死）を回避する

echo "Ready for initial handshake..."
echo "Starting RunPod Serverless Handler (venv)..."
# 仮想環境内のpythonを明示的に使用してハンドラーを起動
# stdout/stderrをボリューム上のファイルにも保存
/runpod-volume/venv/bin/python -u /tmp/my-scripts/rp_handler.py 2>&1 | tee /runpod-volume/handler.log
