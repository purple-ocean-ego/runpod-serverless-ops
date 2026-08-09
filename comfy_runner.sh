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
    # 引数なしの場合は --highvram をデフォルトとして使用（オーバーロード）
    # 引数があれば可変長で ComfyUI 起動フラグとして全て渡す（例: --use-sage-attention 等）
    local args=("${@:---highvram}")
    echo "Starting ComfyUI in the background... (flags: ${args[*]})"
    python main.py \
        --listen 0.0.0.0 \
        --port 8188 \
        --enable-manager \
        --output-directory /runpod-volume/output \
        --input-directory /runpod-volume/input \
        --extra-model-paths-config /tmp/my-scripts/extra_model_paths.yaml \
        "${args[@]}" &
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
    # 引数なしの場合は --highvram をデフォルト値として使用（オーバーロード）
    # 再起動時に start_comfyui へ同じフラグ群を引き継ぐ
    local args=("${@:---highvram}")

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
            
            # 再起動時にフラグ群を引き継いで渡す
            start_comfyui "${args[@]}"
            wait_for_comfyui
            echo "ComfyUI has been restarted with updated settings."
        fi
    fi
}
