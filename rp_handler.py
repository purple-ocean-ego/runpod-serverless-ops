import time
import os
import urllib.request
import urllib.error
import urllib.parse
import json

import runpod

COMFY_API_URL = "http://127.0.0.1:8188"
OUTPUT_DIR = "/runpod-volume/output"

def wait_for_comfyui():
    """
    ComfyUIの起動を待機します。
    コールドスタートタイムアウト（120秒制限）を回避するため、
    この待機はジョブ実行時（Execution Timeoutを消費する形）に行われます。
    """
    print("Waiting for ComfyUI to be fully initialized (checking port 8188)...")
    retries = 0
    max_retries = 30  # 最大5分間待機
    while retries < max_retries:
        try:
            req = urllib.request.Request(f"{COMFY_API_URL}/object_info")
            with urllib.request.urlopen(req) as response:
                if response.status == 200:
                    print("ComfyUI API is up and running! Adding safety margin (10s)...")
                    time.sleep(10)
                    return True
        except urllib.error.URLError:
            pass
        retries += 1
        time.sleep(10)
    
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
    print("Starting RunPod Serverless Handler...")
    runpod.serverless.start({"handler": handler})
