import sys
import json
import os
import requests
import random
import copy
from concurrent.futures import ThreadPoolExecutor, as_completed

def modify_workflow(workflow, seed_mode, index):
    """
    ワークフローJSONを書き換えて、シード値の注入とファイル名の一意化（重複回避）を行う。
    """
    new_workflow = copy.deepcopy(workflow)
    
    # 既存のシード値を取得（固定モードで使用するため）
    existing_seed = None
    for node in new_workflow.values():
        if "KSampler" in node.get("class_type", "") or "Sampler" in node.get("class_type", ""):
            inputs = node.get("inputs", {})
            if "seed" in inputs:
                existing_seed = inputs["seed"]
                break
            if "noise_seed" in inputs:
                existing_seed = inputs["noise_seed"]
                break

    # ターゲットとなるシード値を決定
    if seed_mode == "random":
        target_seed = random.randint(0, 0xffffffffffffffff)
    else:
        target_seed = existing_seed

    # 接頭辞（シード値を埋め込むことで、同一シードなら同一ファイル名になりキャッシュが効くようにする）
    suffix = f"_seed_{target_seed}" if target_seed is not None else f"_{index:03d}"

    for node_id, node in new_workflow.items():
        class_type = node.get("class_type", "")
        inputs = node.get("inputs", {})

        # KSampler系のシード値を書き換え（ランダムモードのみ）
        if seed_mode == "random" and ("KSampler" in class_type or "Sampler" in class_type):
            if "seed" in inputs:
                inputs["seed"] = target_seed
            if "noise_seed" in inputs:
                inputs["noise_seed"] = target_seed

        # SaveImage系のファイル名接頭辞を書き換え
        if "SaveImage" in class_type or "ImageSave" in class_type:
            if "filename_prefix" in inputs:
                current_prefix = inputs["filename_prefix"]
                inputs["filename_prefix"] = f"{current_prefix}{suffix}"
    
    return new_workflow

def send_request(endpoint_id, api_key, workflow_json):
    url = f"https://api.runpod.ai/v2/{endpoint_id}/run"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    payload = {
        "input": {
            "workflow": workflow_json
        }
    }
    
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        return {"error": str(e)}

def main():
    endpoint_id = None
    json_path = None
    count = 1
    seed_mode = "fixed" # デフォルトは固定

    # 1. 引数の処理
    if len(sys.argv) >= 4:
        endpoint_id = sys.argv[1]
        json_path = sys.argv[2]
        count = int(sys.argv[3])
    else:
        # 設定ファイルの読み込み
        config_path = os.path.join(os.getcwd(), "config", "serverless_request.json")
        if os.path.exists(config_path):
            try:
                with open(config_path, "r") as cf:
                    config = json.load(cf)
                    endpoint_id = config.get("endpoint_id")
                    json_path = config.get("json_path")
                    count = int(config.get("count", 1))
                    seed_mode = config.get("seed", "fixed")
            except Exception as e:
                print(f"Error loading config: {e}")
                sys.exit(1)
        else:
            print("Usage: python3 requester.py <ENDPOINT_ID> <JSON_PATH> <COUNT>")
            sys.exit(1)

    api_key = os.getenv("RUNPOD_API_KEY")
    if not api_key:
        print("Error: RUNPOD_API_KEY environment variable is not set.")
        sys.exit(1)

    if not os.path.exists(json_path):
        print(f"Error: JSON file not found at {json_path}")
        sys.exit(1)

    # 2. ベースとなるワークフローJSONの読み込み
    with open(json_path, "r") as f:
        try:
            base_workflow = json.load(f)
        except json.JSONDecodeError:
            print(f"Error: Failed to parse JSON from {json_path}")
            sys.exit(1)

    print(f"Mode: Seed={seed_mode}")
    print(f"Sending {count} requests to endpoint '{endpoint_id}'...")

    # 3. リクエストの送信
    results = []
    with ThreadPoolExecutor() as executor:
        futures = []
        for i in range(1, count + 1):
            # リクエストごとにJSONをカスタマイズ
            custom_workflow = modify_workflow(base_workflow, seed_mode, i)
            futures.append(executor.submit(send_request, endpoint_id, api_key, custom_workflow))
        
        for i, future in enumerate(as_completed(futures), 1):
            res = future.result()
            if "error" in res:
                print(f"[{i:03d}] Error: {res['error']}")
            else:
                job_id = res.get("id", "N/A")
                status = res.get("status", "N/A")
                print(f"[{i:03d}] Success: Job ID = {job_id}")
            results.append(res)

    print("\nSubmission complete.")

if __name__ == "__main__":
    main()
