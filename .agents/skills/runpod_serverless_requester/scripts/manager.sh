#!/bin/bash

# ==============================================================================
# RunPod Serverless Requester Manager
# ==============================================================================

# 設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/requester.py"

# 引数チェック (引数がない場合は設定ファイルを読み込む)
if [ "$#" -lt 1 ]; then
    echo "ヒント: 引数なしで実行すると config/serverless_request.json を読み込みます。"
    echo "個別指定する場合: bash manager.sh <ENDPOINT_ID> <JSON_PATH> <COUNT>"
fi

ENDPOINT_ID=$1
JSON_PATH=$2
COUNT=$3

# APIキーのチェック
if [ -z "$RUNPOD_API_KEY" ]; then
    echo "エラー: 環境変数 RUNPOD_API_KEY が設定されていません。"
    echo "export RUNPOD_API_KEY='your-api-key-here' を実行してから再度お試しください。"
    exit 1
fi

# Python スクリプトの実行
if [ -z "$ENDPOINT_ID" ]; then
    # 引数なし（設定ファイルを読み込む）
    python3 "$PYTHON_SCRIPT"
else
    # 引数あり
    python3 "$PYTHON_SCRIPT" "$ENDPOINT_ID" "$JSON_PATH" "$COUNT"
fi
