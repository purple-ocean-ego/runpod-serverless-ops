#!/bin/bash

# ==============================================================================
# ComfyUI 実行管理ユーティリティ
# ==============================================================================

# --- 変数定義 ---
MANAGER_CONFIG="/runpod-volume/ComfyUI/user/__manager/config.ini"

# -------------------------------------------------------------
# 6. ComfyUI 起動・管理関数
# -------------------------------------------------------------
start_comfyui() {
    echo "Starting ComfyUI in the background..."
    python main.py \
        --listen 0.0.0.0 \
        --port 8188 \
        --enable-manager \
        --output-directory /runpod-volume/output \
        --extra-model-paths-config /tmp/my-scripts/extra_model_paths.yaml \
        --highvram &
    COMFY_PID=$!
}

wait_for_comfyui() {
    local max_retries=100
    local retry_interval=3
    local count=0

    echo "Waiting for ComfyUI to respond on port 8188..."
    while ! curl -s http://localhost:8188 > /dev/null; do
        sleep $retry_interval
        count=$((count + 1))
        
        if ! kill -0 $COMFY_PID 2>/dev/null; then
            echo "Error: ComfyUI process terminated."
            exit 1
        fi

        if [ $count -ge $max_retries ]; then
            echo "Error: ComfyUI timeout."
            exit 1
        fi
        echo "Check $count/$max_retries: Still waiting..."
    done
}

# -------------------------------------------------------------
# 7. セキュリティ設定の適用と再起動
# -------------------------------------------------------------
apply_manager_settings_and_restart() {
    if [ -f "$MANAGER_CONFIG" ]; then
        # 設定の変数を準備
        local update_needed=false
        
        # セキュリティ設定のチェック
        if ! grep -q "security_level = normal" "$MANAGER_CONFIG" || ! grep -q "network_mode = personal_cloud" "$MANAGER_CONFIG"; then
            update_needed=true
        fi
        
        # use_uv を True に設定 (標準 PyTorch 環境なので uv を安全に使用可能)
        if ! grep -q "use_uv = True" "$MANAGER_CONFIG"; then
            update_needed=true
        fi


        if [ "$update_needed" = true ]; then
            echo "Applying Manager settings (Security & UV) and restarting..."
            # セキュリティ
            sed -i 's/security_level = .*/security_level = normal/' "$MANAGER_CONFIG"
            sed -i 's/network_mode = .*/network_mode = personal_cloud/' "$MANAGER_CONFIG"
            
            # UVを有効化 (もし設定がなければ追加、あれば置換)
            if grep -q "use_uv =" "$MANAGER_CONFIG"; then
                sed -i 's/use_uv = .*/use_uv = True/' "$MANAGER_CONFIG"
            else
                echo "use_uv = True" >> "$MANAGER_CONFIG"
            fi

            
            echo "Restarting ComfyUI to apply manager settings..."
            kill $COMFY_PID
            wait $COMFY_PID 2>/dev/null
            
            # 再起動
            start_comfyui
            wait_for_comfyui
            echo "ComfyUI has been restarted with updated settings."
        fi
    fi
}
