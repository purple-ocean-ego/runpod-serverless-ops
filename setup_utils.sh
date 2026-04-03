#!/bin/bash

# ==============================================================================
# ComfyUI 環境構築ユーティリティ
# ==============================================================================

# --- 変数定義 ---
MANAGER_REQ="/runpod-volume/ComfyUI/manager_requirements.txt"
MANAGER_INSTALLED_FLAG="/runpod-volume/venv/.comfyui_manager_installed"
CONSTRAINTS_FILE="/tmp/constraints.txt"

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
# 2. Python 仮想環境の準備 (uv版)
# -------------------------------------------------------------
prepare_venv() {
    # uv が入っていない場合のフォールバック
    if ! command -v uv > /dev/null; then
        echo "Installing uv..."
        pip install uv
    fi

    if [ ! -d "/runpod-volume/venv" ]; then
        echo "Creating python virtual environment with uv..."
        uv venv /runpod-volume/venv --system-site-packages
    fi
    source /runpod-volume/venv/bin/activate

    # ハードリンクエラーによるログの汚れを防止
    export UV_LINK_MODE=copy


    # 起動時の「正しい状態」を記録して制約ファイルを作成
    if [ ! -f "$CONSTRAINTS_FILE" ]; then
        echo "Generating version constraints from base environment..."
        pip freeze | grep -E '^(torch|torchvision|torchaudio|nvidia-|cuda-|triton)' > "$CONSTRAINTS_FILE"
    fi
    
    # 環境変数のエクスポート (Manager 等の外部プロセスにも適用させる)
    export UV_PIP_CONSTRAINTS="$CONSTRAINTS_FILE"
    export PIP_CONSTRAINT="$CONSTRAINTS_FILE"
    echo "Environment constraints applied: $CONSTRAINTS_FILE"

    # PyTorch の状態チェックと修復
    check_pytorch_health
}

# -------------------------------------------------------------
# 2.5 PyTorch の状態チェックと自動修復
# -------------------------------------------------------------
check_pytorch_health() {
    echo "Checking PyTorch health..."
    if ! python -c "import torch; print(f'Torch OK: {torch.__version__} (CUDA: {torch.cuda.is_available()})')" 2>/dev/null; then
        echo "⚠️ PyTorch environment is broken or mismatched. Repairing..."
        # 制約ファイルに基づき、オリジナルのバージョンを再インストール
        # 注意: 指定されたインデックスから確実に cuXX 版を取得する
        uv pip install --force-reinstall --no-cache-dir \
            --index-url https://download.pytorch.org/whl/cu124 \
            -r "$CONSTRAINTS_FILE"

        
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
# 3. ComfyUI 本体のインストール
# -------------------------------------------------------------
install_comfyui() {
    if [ ! -d "/runpod-volume/ComfyUI" ]; then
        echo "Cloning ComfyUI to /runpod-volume/ComfyUI..."
        git clone https://github.com/comfy-org/ComfyUI.git /runpod-volume/ComfyUI
        
        echo "Installing python requirements with uv and strict constraints..."
        # torch などを除外した requirements を作成してインストール
        grep -E -v '^torch(vision|audio)?([>=! ]|$)' /runpod-volume/ComfyUI/requirements.txt > /tmp/req_filtered.txt
        # 明示的に -c で制約ファイルを指定し、環境変数よりも確実に固定する
        uv pip install --no-cache-dir -c "$CONSTRAINTS_FILE" -r /tmp/req_filtered.txt
        
        echo "Adding onnxruntime-gpu..."
        uv pip install --no-cache-dir -c "$CONSTRAINTS_FILE" onnxruntime-gpu

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
            echo "Installing ComfyUI-Manager requirements with uv and strict constraints..."
            if uv pip install --no-cache-dir -c "$CONSTRAINTS_FILE" -r "$MANAGER_REQ"; then
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

