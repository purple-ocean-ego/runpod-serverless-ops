#!/bin/bash

# ==============================================================================
# ComfyUI 環境構築ユーティリティ
# ==============================================================================

# --- 変数定義 ---
MANAGER_REQ="/runpod-volume/ComfyUI/manager_requirements.txt"
MANAGER_INSTALLED_FLAG="/runpod-volume/venv/.comfyui_manager_installed"

# -------------------------------------------------------------
# 1. ネットワークボリュームのディレクトリ構成準備
# -------------------------------------------------------------
prepare_directories() {
    echo "Preparing network volume directories..."
    mkdir -p /runpod-volume/models/checkpoints \
             /runpod-volume/models/clip \
             /runpod-volume/models/clip_vision \
             /runpod-volume/models/configs \
             /runpod-volume/models/controlnet \
             /runpod-volume/models/embeddings \
             /runpod-volume/models/loras \
             /runpod-volume/models/ultralytics/bbox \
             /runpod-volume/models/ultralytics/segm \
             /runpod-volume/models/upscale_models \
             /runpod-volume/models/vae \
             /runpod-volume/models/latent_upscale_models \
             /runpod-volume/models/text_encoders \
             /runpod-volume/custom_nodes \
             /runpod-volume/output
}

# -------------------------------------------------------------
# 2. Python 仮想環境の準備
# -------------------------------------------------------------
prepare_venv() {
    if [ ! -d "/runpod-volume/venv" ]; then
        echo "Creating python virtual environment..."
        python -m venv --system-site-packages /runpod-volume/venv
    fi
    source /runpod-volume/venv/bin/activate
}

# -------------------------------------------------------------
# 3. ComfyUI 本体のインストール
# -------------------------------------------------------------
install_comfyui() {
    if [ ! -d "/runpod-volume/ComfyUI" ]; then
        echo "Cloning ComfyUI to /runpod-volume/ComfyUI..."
        git clone https://github.com/comfy-org/ComfyUI.git /runpod-volume/ComfyUI
        
        echo "Installing python requirements with environment constraints..."
        pip freeze | grep -E '^(torch|torchvision|torchaudio|nvidia-|cuda-|triton)' > /tmp/constraints_fixed.txt
        grep -E -v '^torch(vision|audio)?([>=! ]|$)' /runpod-volume/ComfyUI/requirements.txt > /tmp/req_filtered.txt
        pip install --no-cache-dir -c /tmp/constraints_fixed.txt -r /tmp/req_filtered.txt
        
        echo "Adding onnxruntime-gpu..."
        pip install --no-cache-dir -c /tmp/constraints_fixed.txt onnxruntime-gpu
    fi
}

# -------------------------------------------------------------
# 4. カスタムノードディレクトリの外部化 (シンボリックリンク)
# -------------------------------------------------------------
externalize_custom_nodes() {
    echo "Checking custom_nodes link..."
    if [ -d "/runpod-volume/ComfyUI/custom_nodes" ] && [ ! -L "/runpod-volume/ComfyUI/custom_nodes" ]; then
        echo "Moving existing custom_nodes to central volume..."
        cp -n -r /runpod-volume/ComfyUI/custom_nodes/* /runpod-volume/custom_nodes/ 2>/dev/null || true
        rm -rf /runpod-volume/ComfyUI/custom_nodes
        ln -s /runpod-volume/custom_nodes /runpod-volume/ComfyUI/custom_nodes
    elif [ ! -e "/runpod-volume/ComfyUI/custom_nodes" ]; then
        ln -s /runpod-volume/custom_nodes /runpod-volume/ComfyUI/custom_nodes
    fi
}

# -------------------------------------------------------------
# 5. ComfyUI-Manager (v4) の導入
# -------------------------------------------------------------
install_manager_requirements() {
    if [ -d "/runpod-volume/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
        echo "Removing legacy ComfyUI-Manager..."
        rm -rf /runpod-volume/ComfyUI/custom_nodes/ComfyUI-Manager
    fi

    if [ -f "$MANAGER_REQ" ]; then
        if [ ! -f "$MANAGER_INSTALLED_FLAG" ] || [ "$MANAGER_REQ" -nt "$MANAGER_INSTALLED_FLAG" ]; then
            echo "Installing ComfyUI-Manager requirements..."
            pip freeze | grep -E '^(torch|torchvision|torchaudio|nvidia-|cuda-|triton)' > /tmp/constraints_manager.txt
            if pip install --no-cache-dir -c /tmp/constraints_manager.txt -r "$MANAGER_REQ"; then
                touch "$MANAGER_INSTALLED_FLAG"
                echo "ComfyUI-Manager requirements installed successfully."
            else
                echo "Error: Failed to install ComfyUI-Manager requirements."
            fi
        else
            echo "ComfyUI-Manager requirements are up-to-date."
        fi
    fi
}
