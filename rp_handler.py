import time
import os
import urllib.request
import urllib.error
import urllib.parse
import json

import runpod

import subprocess

COMFY_API_URL = "http://127.0.0.1:8188"
OUTPUT_DIR = "/runpod-volume/output"

is_comfyui_started = False

def start_comfyui():
    """
    ComfyUIのプロセスをバックグラウンドで起動します。
    """
    print("Launching ComfyUI in the background...", flush=True)
    try:
        # 仮想環境内のpythonを絶対パスで使用
        python_path = "/runpod-volume/venv/bin/python"
        cmd = [
            python_path, "-u", "/runpod-volume/ComfyUI/main.py",
            "--listen", "127.0.0.1",
            "--port", "8188",
            "--output-directory", "/runpod-volume/output",
            "--extra-model-paths-config", "/tmp/my-scripts/extra_model_paths.yaml",
            "--highvram"
        ]
        # stdout/stderrは引き続きファイルに保存
        with open("/runpod-volume/comfyui.log", "w") as log_file:
            subprocess.Popen(cmd, stdout=log_file, stderr=log_file, cwd="/runpod-volume/ComfyUI")
        print("ComfyUI launch command executed.", flush=True)
    except Exception as e:
        print(f"Error launching ComfyUI: {str(e)}", flush=True)

def wait_for_comfyui():
    """
    ComfyUIの起動を待機します。リクエストが来た時に初めて起動します。
    """
    global is_comfyui_started
    if not is_comfyui_started:
        start_comfyui()
        is_comfyui_started = True
        # 起動直後のポーリング失敗を避けるため、最初のチェック前に少し待つ
        time.sleep(2)

    print("Waiting for ComfyUI to be fully initialized (checking port 8188)...", flush=True)

    retries = 0
    max_retries = 100  # 3秒×100回 = 最大5分間待機
    while retries < max_retries:
        try:
            req = urllib.request.Request(f"{COMFY_API_URL}/object_info")
            # タイムアウト付きでリクエスト（無限ハング防止）
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    print("ComfyUI API is up and running! Adding safety margin (3s)...", flush=True)
                    time.sleep(3)
                    return True
        except (urllib.error.URLError, TimeoutError, Exception):
            pass
        retries += 1
        time.sleep(3)
    
    raise Exception("ComfyUI failed to start within the expected time.")

def handler(job):
    """
    RunPod Serverlessのメインハンドラー。
    ジョブの内容を受け取り、ComfyUIへAPIリクエストを投げ、生成完了を待って結果を返します。
    """
    # ジョブを受け取ったら、まずバックグラウンドのComfyUIがAPI受付可能になるまで待つ
    wait_for_comfyui()
    
    job_input = job.get("input", {})
    if "workflow" not in job_input:
        return {"error": "Missing 'workflow' in input (JSON format required)"}
    
    workflow = job_input["workflow"]
    
    # ======================================================
    # 1. ComfyUIへPrompt(Workflow)を送信
    # ======================================================
    try:
        data = json.dumps({"prompt": workflow}).encode("utf-8")
        req = urllib.request.Request(f"{COMFY_API_URL}/prompt", data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req) as response:
            resp_data = json.loads(response.read().decode('utf-8'))
            prompt_id = resp_data.get("prompt_id")
    except Exception as e:
        return {"error": f"Failed to submit workflow to ComfyUI: {str(e)}"}
    
    if not prompt_id:
        return {"error": "Did not receive prompt_id from ComfyUI"}

    # ======================================================
    # 2. 生成完了をポーリングにて監視
    # ======================================================
    completed = False
    hist_data = None
    
    while not completed:
        try:
            hist_req = urllib.request.Request(f"{COMFY_API_URL}/history/{prompt_id}")
            with urllib.request.urlopen(hist_req) as hist_resp:
                if hist_resp.status == 200:
                    hist_data = json.loads(hist_resp.read().decode('utf-8'))
                    if prompt_id in hist_data:
                        # 生成履歴に今回のprompt_idが含まれていれば完了
                        completed = True
                        break
        except urllib.error.URLError:
            pass
        
        # 1秒間隔でポーリング
        time.sleep(1)
        
    # ======================================================
    # 3. 生成されたファイルの結果計算
    # ======================================================
    generated_count = 0
    total_size_bytes = 0
    
    if hist_data and prompt_id in hist_data:
        prompt_history = hist_data[prompt_id]
        outputs = prompt_history.get("outputs", {})
        
        # 履歴に含まれる全ノードの出力を走査
        for node_id, node_output in outputs.items():
            if "images" in node_output:
                for image in node_output["images"]:
                    filename = image.get("filename")
                    subfolder = image.get("subfolder", "")
                    
                    # 出力された画像の実ファイルサイズを取得
                    file_path = os.path.join(OUTPUT_DIR, subfolder, filename)
                    if os.path.exists(file_path):
                        generated_count += 1
                        total_size_bytes += os.path.getsize(file_path)

    return {
        "status": "success",
        "message": "Images generated successfully.",
        "prompt_id": prompt_id,
        "generated_count": generated_count,
        "total_size_bytes": total_size_bytes
    }

if __name__ == "__main__":
    try:
        print("Starting RunPod Serverless Handler...", flush=True)
        runpod.serverless.start({"handler": handler})
    except Exception as e:
        print(f"CRITICAL: Handler failed to start or crashed: {str(e)}", flush=True)
        import traceback
        traceback.print_exc()
        # クラッシュ時に少し待ってログがフラッシュされるようにする
        time.sleep(2)

