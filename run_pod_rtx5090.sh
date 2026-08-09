#!/bin/bash

# ==============================================================================
# RTX 5090 (Blackwell) 専用 ComfyUI ポッド起動スクリプト
# MiniMax H3 等の RTX 5090 検証用。詳細は docs/minimax_h3_rtx5090.md を参照。
#
# 使い方:
#   bash run_pod_rtx5090.sh [--pytorch-index <URL>] [ComfyUI起動フラグ...]
#
# - --pytorch-index <URL>: 既定 values は cu130 を指定済み。変更する場合のみ指定
# - 残りの引数はすべて ComfyUI の起動フラグとして渡される
# ==============================================================================

# 自ディレクトリの取得 (外部ファイル読み込み用)
SCRIPT_DIR=$(cd $(dirname $0); pwd)

# 環境変数 PYTORCH_INDEX が外部で設定済みか確認
# （setup_utils.sh を source すると cu126 の既定値が代入されるため、その前に記録する）
PYTORCH_INDEX_USER_SET=false
[ -n "${PYTORCH_INDEX+x}" ] && PYTORCH_INDEX_USER_SET=true

# ユーティリティの読み込み
source "${SCRIPT_DIR}/setup_utils.sh"
source "${SCRIPT_DIR}/comfy_runner.sh"

# --- 引数解析 ---
# --pytorch-index は setup_utils.sh の PYTORCH_INDEX を上書き
PYTORCH_INDEX_ARG=""
COMFY_ARGS=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --pytorch-index)
            PYTORCH_INDEX_ARG="$2"
            shift 2
            ;;
        --pytorch-index=*)
            PYTORCH_INDEX_ARG="${1#*=}"
            shift
            ;;
        *)
            COMFY_ARGS+=("$1")
            shift
            ;;
    esac
done

# RTX 5090 既定の cu130 を適用（--pytorch-index 指定 or 外部環境変数が無い場合のみ）
if [ -n "$PYTORCH_INDEX_ARG" ]; then
    export PYTORCH_INDEX="$PYTORCH_INDEX_ARG"
elif [ "$PYTORCH_INDEX_USER_SET" = "false" ]; then
    export PYTORCH_INDEX="https://download.pytorch.org/whl/cu130"
fi

# 可変長引数（未指定なら既定の --highvram）
if [ ${#COMFY_ARGS[@]} -eq 0 ]; then
    COMFY_ARGS+=("--highvram")
fi

echo "=== RTX 5090 Pod Setup ==="
echo "PYTORCH_INDEX: ${PYTORCH_INDEX}"
echo "ComfyUI flags: ${COMFY_ARGS[*]}"

# ==============================================================================
# メイン実行セクション
# ==============================================================================

# 1. 前準備
prepare_directories
uv pip list > /runpod-volume/venv_pip_list.txt 2>/dev/null || true

# 2. 環境構築
prepare_venv

# RTX 5090 (sm_120 / CUDA 13.0) では FlashAttention は非対応のため導入しない
# SageAttention は内蔵 --use-sage-attention または KJ ノードの Patch Sage Attention で利用
install_sageattention

install_comfyui
externalize_custom_nodes

install_manager_requirements
sync_custom_node_requirements

# 3. 起動フロー
cd /runpod-volume/ComfyUI
start_comfyui "${COMFY_ARGS[@]}"
wait_for_comfyui

# 4. 設定適用 (初回起動後に config.ini が作られるのを待ってから適用)
apply_manager_settings_and_restart "${COMFY_ARGS[@]}"

echo "ComfyUI is now ready (RTX 5090) and accessible on port 8188!"