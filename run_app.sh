#!/bin/bash

# ComfyUIの永続化しておきたいモデルやカスタムノードの置き場所をネットワークボリュームに指定
mkdir -p /runpod-volume/models
mkdir -p /runpod-volume/custom_nodes
mkdir -p /runpod-volume/models/checkpoints
mkdir -p /runpod-volume/models/clip
mkdir -p /runpod-volume/models/clip_vision
mkdir -p /runpod-volume/models/configs
mkdir -p /runpod-volume/models/controlnet
mkdir -p /runpod-volume/models/embeddings
mkdir -p /runpod-volume/models/loras
mkdir -p /runpod-volume/models/ultralytics
mkdir -p /runpod-volume/models/ultralytics/bbox
mkdir -p /runpod-volume/models/ultralytics/segm
mkdir -p /runpod-volume/models/upscale_models
mkdir -p /runpod-volume/models/vae
mkdir -p /runpod-volume/output

# Pythonの仮想環境をネットワークボリュームに作成・有効化
if [ ! -d "/runpod-volume/venv" ]; then
    echo "Creating python virtual environment..."
    python -m venv --system-site-packages /runpod-volume/venv
fi
source /runpod-volume/venv/bin/activate

# ComfyUI本体のネットワークボリュームへの導入・永続化
if [ ! -d "/runpod-volume/ComfyUI" ]; then
    echo "Cloning ComfyUI to /runpod-volume/ComfyUI..."
    git clone https://github.com/comfy-org/ComfyUI.git /runpod-volume/ComfyUI
    echo "Installing python requirements..."
    pip install -r /runpod-volume/ComfyUI/requirements.txt
    
    echo "Fixing torchaudio version mismatch and adding onnxruntime-gpu..."
    pip install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
    pip install onnxruntime-gpu
fi

# -------------------------------------------------------------
# カスタムノードの外部ディレクトリ化（既設ノードを壊さない安全な処理）
# -------------------------------------------------------------
if [ -d "/runpod-volume/ComfyUI/custom_nodes" ] && [ ! -L "/runpod-volume/ComfyUI/custom_nodes" ]; then
    echo "Externalizing custom_nodes directory to /runpod-volume/custom_nodes..."
    # 既存のファイルを安全に移動（上書き禁止）し、元の実体フォルダを削除してリンクに差し替える
    cp -n -r /runpod-volume/ComfyUI/custom_nodes/* /runpod-volume/custom_nodes/ 2>/dev/null || true
    rm -rf /runpod-volume/ComfyUI/custom_nodes
    ln -s /runpod-volume/custom_nodes /runpod-volume/ComfyUI/custom_nodes
    echo "custom_nodes has been successfully linked to /runpod-volume/custom_nodes."
elif [ ! -e "/runpod-volume/ComfyUI/custom_nodes" ]; then
    # 実体もリンクもなければ新規でリンクを貼る
    ln -s /runpod-volume/custom_nodes /runpod-volume/ComfyUI/custom_nodes
fi

# -------------------------------------------------------------
# ComfyUI-Manager v4の導入
# v4からcustom_nodesへのgit cloneは廃止され、pipインストールに変更されました。
# -------------------------------------------------------------
if [ -d "/runpod-volume/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    echo "Removing legacy ComfyUI-Manager (custom_nodes/ComfyUI-Manager) to prevent conflicts..."
    rm -rf /runpod-volume/ComfyUI/custom_nodes/ComfyUI-Manager
fi

MANAGER_REQ="/runpod-volume/ComfyUI/manager_requirements.txt"
MANAGER_INSTALLED_FLAG="/runpod-volume/venv/.comfyui_manager_installed"

if [ -f "$MANAGER_REQ" ]; then
    # マーカーファイルが存在しない、または requirements.txt の方が新しい場合にインストールを実行
    if [ ! -f "$MANAGER_INSTALLED_FLAG" ] || [ "$MANAGER_REQ" -nt "$MANAGER_INSTALLED_FLAG" ]; then
        echo "Installing/Updating ComfyUI-Manager (v4) requirements..."
        if pip install -r "$MANAGER_REQ"; then
            touch "$MANAGER_INSTALLED_FLAG"
            echo "ComfyUI-Manager requirements installed successfully."
        else
            echo "Error: Failed to install ComfyUI-Manager requirements."
        fi
    else
        echo "ComfyUI-Manager requirements are already up-to-date. Skipping pip install."
    fi
else
    echo "Warning: manager_requirements.txt not found. ComfyUI might need to be updated."
fi

# ComfyUIをバックグラウンドで起動
cd /runpod-volume/ComfyUI
echo "Starting ComfyUI in the background..."
python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-manager \
    --output-directory /runpod-volume/output \
    --extra-model-paths-config /tmp/my-scripts/extra_model_paths.yaml &

# 起動完了を待機 (3秒おきに最大100回 = 5分間)
MAX_RETRIES=100
RETRY_INTERVAL=3
COUNT=0

echo "Waiting for ComfyUI to respond on port 8188 (up to 5 minutes)..."
while ! curl -s http://localhost:8188 > /dev/null; do
    sleep $RETRY_INTERVAL
    COUNT=$((COUNT + 1))
    
    # プロセスがまだ生きているか確認
    if ! kill -0 $! 2>/dev/null; then
        echo "Error: ComfyUI process has terminated unexpectedly."
        exit 1
    fi

    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Error: ComfyUI failed to respond on port 8188 within 5 minutes."
        exit 1
    fi
    echo "Check $COUNT/$MAX_RETRIES: Still waiting for ComfyUI..."
done

echo "ComfyUI is now ready and accessible on port 8188!"