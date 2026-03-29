---
name: RunPod Serverless Requester
description: ComfyUI API JSON を RunPod Serverless エンドポイントに非同期でリクエストします。
---
# RunPod Serverless Requester

このスキルは、ComfyUI の API JSON ファイルを RunPod Serverless エンドポイントへ指定した回数分、一括で送信しキューイングするためのツールです。

## 特長
- `ThreadPoolExecutor` を使用した高い同時リクエスト性能。
- 投入後は `job_id` のみを出力し、実際の生成状況は RunPod のコンソールまたは他のツールで確認する「投げっぱなし」型です。
- クライアント側での長い待機時間を必要としません。

## 前提条件
- **API キー**: RunPod の API キーを環境変数 `RUNPOD_API_KEY` に設定している必要があります。
  ```bash
  export RUNPOD_API_KEY="your-runpod-api-key"
  ```
- **Python 3**: `requests` モジュールがインストールされている必要があります。

## 使い方
引数にエンドポイントID、JSONパス、リクエスト回数を指定して実行します。
引数を省略した場合は、`config/serverless_request.json` の設定が読み込まれます。

```bash
# 引数を個別に指定する場合
bash .agents/skills/runpod_serverless_requester/scripts/manager.sh <ENDPOINT_ID> <JSON_PATH> <COUNT>

# 設定ファイルを使用する場合
bash .agents/skills/runpod_serverless_requester/scripts/manager.sh
```

### 設定ファイルの例 (`config/serverless_request.json`)
初めて使用する場合は、`config/serverless_request.json.sample` をコピーして作成してください。
```json
{
  "endpoint_id": "vllm-xxxxx",
  "json_path": "./workflow.json",
  "count": 5,
  "seed": "random"
}
```

#### シード設定 (`seed`)
- `"random"`: 各リクエストごとに異なるシード値を生成し、ファイル名に付与します（競合回避のため、`_seed_{シード値}` がファイル名に追加されます）。
- `"fixed"`: 元のJSONに記載されたシード値を維持します（ファイル名のprefixも同じ `_seed_{シード値}` になることで、キャッシュが働き、同じ内容の異なるファイルが大量生成されないようにします）。

### 例
```bash
# workflow.json を vllm-xxxxx に 10 回リクエスト
bash .agents/skills/runpod_serverless_requester/scripts/manager.sh vllm-123456 workflow.json 10
```

## 構成
- `config/serverless_request.json.sample`: 設定ファイルのテンプレート。
- `scripts/requester.py`: 非同期リクエスト処理の本体（Python）。設定ファイルの読み込みにも対応。
- `scripts/manager.sh`: 引数チェックを行う Bash ラッパー。
