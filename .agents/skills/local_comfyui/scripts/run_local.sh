#!/bin/bash

# ==============================================================================
# ComfyUI ローカル開発環境 起動スクリプト (Skill 実体版)
# ==============================================================================
# Docker イメージのビルドとコンテナの起動を行う。
# 永続ストレージはリポジトリ外の $HOME/comfyui-local に配置される。
#
# 使い方:
#   bash run_local.sh          # デフォルトパスで起動
#   COMFYUI_WORKSPACE=~/my-comfy bash run_local.sh  # パスを変更
#
# コンテナ停止:
#   docker stop comfyui-local-dev
#
# コンテナ再起動:
#   docker start comfyui-local-dev
#
# コンテナ内でコマンド実行:
#   docker exec -it comfyui-local-dev bash

set -e

CONTAINER_NAME="comfyui-local-dev"
IMAGE_NAME="comfyui-local-dev"
PORT=8188

# 永続ストレージのパス（環境変数で上書き可能）
WORKSPACE="${COMFYUI_WORKSPACE:-$HOME/comfyui-local}"

# スクリプトの格納ディレクトリ（Dockerfile.local 等がある場所）
SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)

echo "===================================================================="
echo "  🚀 ComfyUI Local Dev Environment Launcher"
echo "===================================================================="
echo "  Workspace: $WORKSPACE"
echo "  Image:     $IMAGE_NAME"
echo "  Container: $CONTAINER_NAME"
echo "  Port:      $PORT"
echo "===================================================================="

# -------------------------------------------------------------
# 1. 永続ディレクトリ群の自動作成
# -------------------------------------------------------------
echo ""
echo "📁 Preparing workspace directories..."
mkdir -p "$WORKSPACE"/{ComfyUI,custom_nodes,output,input}
mkdir -p "$WORKSPACE"/models/{audio_encoders,checkpoints,clip,clip_vision,configs,controlnet}
mkdir -p "$WORKSPACE"/models/{diffusion_models,embeddings,latent_upscale_models,LLM,loras}
mkdir -p "$WORKSPACE"/models/{model_patches,sam,sam3,text_encoders,unet,upscale_models,vae}
mkdir -p "$WORKSPACE"/models/ultralytics/{bbox,segm}
echo "✅ Workspace ready."

# -------------------------------------------------------------
# 2. 既存コンテナの停止・削除
# -------------------------------------------------------------
if [ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
    echo ""
    echo "⚠️  Found existing container '${CONTAINER_NAME}'. Stopping and removing..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# -------------------------------------------------------------
# 3. ローカル専用イメージのビルド
# -------------------------------------------------------------
echo ""
echo "🐳 Building Docker image from Dockerfile.local..."
docker build --network host -f "$SCRIPT_DIR/Dockerfile.local" -t "$IMAGE_NAME" "$SCRIPT_DIR"

# -------------------------------------------------------------
# 4. コンテナ起動
# -------------------------------------------------------------
echo ""
echo "🔥 Starting container with GPU access..."
docker run --gpus all \
  -d \
  -p ${PORT}:${PORT} \
  -v "$WORKSPACE/ComfyUI:/workspace/ComfyUI" \
  -v "$WORKSPACE/models:/workspace/models" \
  -v "$WORKSPACE/custom_nodes:/workspace/custom_nodes" \
  -v "$WORKSPACE/output:/workspace/output" \
  -v "$WORKSPACE/input:/workspace/input" \
  -v "$SCRIPT_DIR:/scripts:ro" \
  -v "$SCRIPT_DIR/extra_model_paths_local.yaml:/workspace/extra_model_paths.yaml:ro" \
  --name "$CONTAINER_NAME" \
  "$IMAGE_NAME"

echo ""
echo "===================================================================="
echo "🎉 ComfyUI container started successfully!"
echo "--------------------------------------------------------------------"
echo "  🌐 Access ComfyUI:  http://localhost:${PORT}"
# relative display on host side:
echo "  📂 Workspace:       $WORKSPACE"
echo "  📝 View logs:       docker logs -f ${CONTAINER_NAME}"
echo "  🔧 Enter container: docker exec -it ${CONTAINER_NAME} bash"
echo "  🛑 Stop:            docker stop ${CONTAINER_NAME}"
echo "  ▶️  Restart:         docker start ${CONTAINER_NAME}"
echo "===================================================================="
