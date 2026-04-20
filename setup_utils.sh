#!/bin/bash

# ==============================================================================
# ComfyUI 環境構築ユーティリティ (Pure uv アーキテクチャ版)
# ==============================================================================

# --- 変数定義 ---
MANAGER_REQ="/runpod-volume/ComfyUI/manager_requirements.txt"
MANAGER_INSTALLED_FLAG="/runpod-volume/venv/.comfyui_manager_installed"
PYTORCH_INDEX="https://download.pytorch.org/whl/cu126"

# uv のグローバル設定 (Manager 等の外部 uv 呼び出しにも適用される)
export UV_EXTRA_INDEX_URL="$PYTORCH_INDEX"
export UV_LINK_MODE=copy

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
             /runpod-volume/models/LLM \
             /runpod-volume/models/loras \
             /runpod-volume/models/ultralytics/bbox \
             /runpod-volume/models/ultralytics/segm \
             /runpod-volume/models/upscale_models \
             /runpod-volume/models/unet \
             /runpod-volume/models/diffusion_models \
             /runpod-volume/models/vae \
             /runpod-volume/models/latent_upscale_models \
             /runpod-volume/models/text_encoders \
             /runpod-volume/models/audio_encoders \
             /runpod-volume/models/model_patches \
             /runpod-volume/custom_nodes \
             /runpod-volume/output \
             /runpod-volume/input
}

# -------------------------------------------------------------
# 2. Python 仮想環境の準備 (Pure uv版)
# -------------------------------------------------------------
prepare_venv() {
    if [ ! -d "/runpod-volume/venv" ]; then
        echo "Creating python virtual environment with uv (Python 3.12)..."
        uv venv /runpod-volume/venv --python 3.12
    fi
    source /runpod-volume/venv/bin/activate

    # PyTorch が未インストールなら導入
    if ! python -c "import torch" 2>/dev/null; then
        echo "Installing PyTorch (cu126) with uv..."
        uv pip install --no-cache-dir \
            torch torchvision torchaudio \
            --index-url "$PYTORCH_INDEX"
    fi

    # PyTorch の状態チェック
    check_pytorch_health

    # huggingface-cli (huggingface_hub) の導入
    if ! python -c "import huggingface_hub" 2>/dev/null; then
        echo "Installing huggingface_hub (huggingface-cli) with uv..."
        uv pip install --no-cache-dir huggingface_hub
    fi
}

# -------------------------------------------------------------
# 2.5 PyTorch の状態チェックと自動修復
# -------------------------------------------------------------
check_pytorch_health() {
    echo "Checking PyTorch health..."
    if ! python -c "import torch; print(f'Torch OK: {torch.__version__} (CUDA: {torch.cuda.is_available()})')" 2>/dev/null; then
        echo "⚠️ PyTorch environment is broken or mismatched. Repairing with uv..."
        uv pip install --no-cache-dir --reinstall \
            torch torchvision torchaudio \
            --index-url "$PYTORCH_INDEX"
        
        if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
            echo "✅ PyTorch repair successful."
        else
            echo "❌ PyTorch repair failed. Manual intervention may be needed."
        fi
    else
        echo "✅ PyTorch environment looks healthy."
    fi
}


# -------------------------------------------------------------
# 2.7 llama-cpp-python (GPU対応) の導入
# -------------------------------------------------------------
install_llama_cpp() {
    if python -c "import llama_cpp" 2>/dev/null; then
        echo "✅ llama-cpp-python is already installed."
        return 0
    fi

    echo "Installing llama-cpp-python with CUDA support..."
    # CMAKE_ARGS="-DGGML_CUDA=on" を付与してビルド
    CMAKE_ARGS="-DGGML_CUDA=on" \
        uv pip install --no-cache-dir llama-cpp-python

    if python -c "import llama_cpp; print(f'llama-cpp-python OK: {llama_cpp.__version__}')" 2>/dev/null; then
        echo "✅ llama-cpp-python installed successfully."
    else
        echo "⚠️ llama-cpp-python installation may have issues."
    fi
}


# -------------------------------------------------------------
# 3. ComfyUI 本体のインストール
# -------------------------------------------------------------
install_comfyui() {
    if [ ! -d "/runpod-volume/ComfyUI" ]; then
        echo "Cloning ComfyUI to /runpod-volume/ComfyUI..."
        git clone https://github.com/comfy-org/ComfyUI.git /runpod-volume/ComfyUI
        
        echo "Installing python requirements with uv..."
        uv pip install --no-cache-dir -r /runpod-volume/ComfyUI/requirements.txt
        
        echo "Adding onnxruntime-gpu..."
        uv pip install --no-cache-dir onnxruntime-gpu
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
            echo "Installing ComfyUI-Manager requirements with uv..."
            if uv pip install --no-cache-dir -r "$MANAGER_REQ"; then
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
