#!/bin/bash

# ==============================================================================
# RunPod Serverless起動スクリプト
# ==============================================================================
# 複数コンテナが同時に立ち上がった際の競合を防ぐため、
# ネットワークボリュームの操作（ディレクトリ構築・git clone・pip install）は
# flock コマンドにより排他ロックをかけて実行します。

LOCK_FILE="/runpod-volume/setup.lock"

echo "Acquiring lock for setup..."
(
    flock -x 200

    echo "Lock acquired. Proceeding with setup..."

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
    # ロック内でもactivateし、必要なパッケージがあれば入れる
    source /runpod-volume/venv/bin/activate

    # Serverlessハンドラ用追加ライブラリ (Dockerfileにも記載しているが念のためvenvにも導入)
    pip install -q runpod requests

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

    # ComfyUI-Manager等、Serverlessで不要な処理はスキップしています
    
    echo "Setup finished. Releasing lock..."
) 200>"$LOCK_FILE"


# ==============================================================================
# ComfyUI 起動シーケンス
# ==============================================================================
# ロック外で環境を有効化して起動
source /runpod-volume/venv/bin/activate

cd /runpod-volume/ComfyUI
echo "Starting ComfyUI in the background... (Logs: /runpod-volume/comfyui.log)"
# ログをネットワークボリュームに保存するように変更
python main.py \
    --listen 127.0.0.1 \
    --port 8188 \
    --output-directory /runpod-volume/output \
    --extra-model-paths-config /tmp/my-scripts/extra_model_paths.yaml \
    > /runpod-volume/comfyui.log 2>&1 &

# 起動完了を待機 (20秒おきに最大15回 = 5分間)
MAX_RETRIES=30
RETRY_INTERVAL=20
COUNT=0

echo "Waiting for ComfyUI to respond on port 8188 and load nodes (checking /object_info)..."
while ! curl -s http://127.0.0.1:8188/object_info | jq -e '.["CheckpointLoaderSimple"]' > /dev/null 2>&1; do
    sleep $RETRY_INTERVAL
    COUNT=$((COUNT + 1))
    
    # プロセスがまだ生きているか確認
    if ! kill -0 $! 2>/dev/null; then
        echo "Error: ComfyUI process has terminated unexpectedly. Check /runpod-volume/comfyui.log for details."
        exit 1
    fi

    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Error: ComfyUI failed to become ready within 10 minutes."
        exit 1
    fi
    echo "Check $COUNT/$MAX_RETRIES: Still waiting for ComfyUI to initialize nodes..."
done

echo "ComfyUI reported node availability. Adding 10s safety margin..."
sleep 10

echo "ComfyUI is now ready!"
echo "Starting RunPod Serverless Handler in foreground..."

# ハンドラーをフォアグラウンド実行し、APIリクエストを待ち受ける
# （スクリプトはここでブロックされ、コンテナの稼働を維持します）
python /tmp/my-scripts/rp_handler.py
