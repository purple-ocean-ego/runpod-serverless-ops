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

    # Alekpet 等のカスタムノードとの互換性のために pip 本体を導入 (置物として利用)
    if ! python -c "import pip" 2>/dev/null; then
        echo "📦 Installing pip for custom node compatibility..."
        uv pip install --no-cache-dir pip
    fi

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
# 2.7 llama-cpp-python (JamePeng Fork - Qwen3-VL対応) の導入
# -------------------------------------------------------------
install_llama_cpp() {
    if python -c "import llama_cpp" 2>/dev/null; then
        echo "✅ llama-cpp-python is already installed."
        return 0
    fi

    echo "🚀 Installing JamePeng fork of llama-cpp-python (Priority Build)..."
    local FORK_URL="git+https://github.com/JamePeng/llama-cpp-python.git"
    
    # CMAKE_ARGS="-DGGML_CUDA=on" FORCE_CMAKE=1 を付与
    # --no-binary を指定してソースからのビルドを強制
    CMAKE_ARGS="-DGGML_CUDA=on" FORCE_CMAKE=1 \
        uv pip install --no-cache-dir --no-binary llama-cpp-python \
        "llama-cpp-python @ ${FORK_URL}"

    if python -c "import llama_cpp; print(f'llama-cpp-python (Fork) OK: {llama_cpp.__version__}')" 2>/dev/null; then
        echo "✅ JamePeng fork of llama-cpp-python installed successfully."
    else
        echo "❌ llama-cpp-python installation failed."
    fi
}


# -------------------------------------------------------------
# 3. ComfyUI 本体のインストールと依存関係の自動チェック
# -------------------------------------------------------------
install_comfyui() {
    if [ ! -d "/runpod-volume/ComfyUI" ]; then
        echo "Cloning ComfyUI to /runpod-volume/ComfyUI..."
        git clone https://github.com/comfy-org/ComfyUI.git /runpod-volume/ComfyUI
    fi

    # 依存関係（特に最近必須となった sqlalchemy 等）の存在をチェック
    # チェック自体は 0.1秒未満で終わるため、起動速度への影響はない
    if ! python -c "import sqlalchemy, aiohttp" 2>/dev/null; then
        echo "⚠️ Missing mandatory ComfyUI dependencies. Installing/Updating with uv..."
        uv pip install --no-cache-dir -r /runpod-volume/ComfyUI/requirements.txt
        
        # 万が一 requirements.txt が古く、sqlalchemy が含まれていない場合に備えて個別追加
        uv pip install --no-cache-dir sqlalchemy aiohttp
        
        if python -c "import sqlalchemy" 2>/dev/null; then
            echo "✅ ComfyUI requirements repaired successfully."
        else
            echo "❌ Failed to install mandatory requirements."
        fi
    else
        echo "✅ ComfyUI requirements are already satisfied."
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

# -------------------------------------------------------------
# 6. すべての内部カスタムノードの依存関係を同期
# -------------------------------------------------------------
sync_custom_node_requirements() {
    if [ ! -d "/runpod-volume/custom_nodes" ]; then
        return 0
    fi

    echo "🔍 Scanning and syncing requirements for all custom nodes..."
    
    # [競合の事前解決] Impact-Pack 等で要求される iopath を安全に PyPI から最新化
    # 戦略を一時的に unsafe-best-match にして PyPI 本家の最新版を強制的に認識させる
    echo "📦 Pre-resolving mandatory dependencies (iopath)..."
    uv pip install --no-cache-dir --index-strategy unsafe-best-match "iopath>=0.1.10"

    # [ループの堅牢化] FD 3 を使用して、ループ内の uv が入力を消費するのを防止
    find /runpod-volume/custom_nodes -maxdepth 2 -name "requirements.txt" | while read -r -u 3 req_file; do
        echo "📦 Installing from: $req_file"
        uv pip install --no-cache-dir -r "$req_file"
    done 3<&0

    echo "✅ Custom node requirements sync finished."
}
