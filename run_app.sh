#!/bin/bash

# ComfyUIの永続化しておきたいモデル等の置き場所をネットワークボリュームに指定
mkdir -p /runpod-volume/models
mkdir -p /runpod-volume/models/checkpoints
mkdir -p /runpod-volume/models/clip
mkdir -p /runpod-volume/models/clip_vision
mkdir -p /runpod-volume/models/configs
mkdir -p /runpod-volume/models/controlnet
mkdir -p /runpod-volume/models/embeddings
mkdir -p /runpod-volume/models/loras
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
fi

# ComfyUI-Managerの導入（まだ存在しない場合）
if [ ! -d "/runpod-volume/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    echo "Cloning ComfyUI-Manager..."
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git /runpod-volume/ComfyUI/custom_nodes/ComfyUI-Manager
    echo "Installing ComfyUI-Manager python requirements..."
    pip install -r /runpod-volume/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt
fi

# ComfyUIを起動
cd /runpod-volume/ComfyUI
echo "Starting ComfyUI from /runpod-volume/ComfyUI..."
python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-manager \
    --output-directory /runpod-volume/output \
    --extra-model-paths-config /tmp/my-scripts/extra_model_paths.yaml