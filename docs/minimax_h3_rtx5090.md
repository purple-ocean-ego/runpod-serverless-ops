# MiniMax H3 on RTX 5090

本ドキュメントは、RTX 5090（Blackwell / sm_120）上で MiniMax H3 を ComfyUI にて試すためのセットアップ手順をまとめたものです。
この標準的な起動手順（`run_app.sh`)については README を、RTX 5090 用イメージの構成については README の「RTX 5090 対応」節を参照してください。

## 1. 前提

- RunPod Pod（RTX 5090, 32GB VRAM）
- Docker イメージ: `runpod/base:1.1.0-cuda1300-ubuntu2404`（CUDA 13.0）
- PyTorch: `cu130`（`PYTORCH_INDEX` で指定）
- ComfyUI: **0.30.0 以上**（H3 ネイティブ対応は 0.30.0 でマージ済み）
- 起動スクリプト: `run_pod_rtx5090.sh`

## 2. ネットワークボリュームの初期化

既存のボリュームを使い回す場合、**ComfyUI / custom_nodes / venv は手動削除**してからやり直してください:

```
rm -rf /runpod-volume/ComfyUI
rm -rf /runpod-volume/custom_nodes
rm -rf /runpod-volume/venv
```

（不要なカスタムノード（ImpactPack 等）の起動遅延もこれで解消されます。モデル（models）は削除しない。）

## 3. モデルファイル（手動配置）

`extra_model_paths.yaml` のマップ先に合わせて配置します。本プロジェクトは **R2V 運用が基本** のため、Ref2VA が必須です。

| ファイル | 配置先 | サイズ目安 | 備考 |
|---|---|---|---|
| `minimax_h3_ref2va_pruned_int8_convrot.safetensors` | `models/diffusion_models/` | ~20.9 GB | **R2V 用（必須）** |
| `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | `models/text_encoders/` | ~14.6 GB | NVFP4 エンコーダ。CLIPLoader の type は `minimax` |
| `minimax_h3_video_vae_fp16.safetensors` | `models/vae/` | — | 必須 |
| `minimax_h3_audio_vae_fp32.safetensors` | `models/vae/` | — | 必須（音声生成に必要） |
| `minimax_h3_fl2va_pruned_int8_convrot.safetensors` | `models/diffusion_models/` | ~19.5 GB | **任意**（I2V / T2V / 継続チェーン用。FL2VAとは別チェックポイント） |

- 出典: `Comfy-Org/MiniMax-H3`（Hugging Face）を推奨
- R2V のみなら Ref2VA + エンコーダ + VAE 2点（計 ~40GB）。後で I2V / T2V も使うなら FL2VA を追加（計 ~60GB）
- 注意: **Ref2VA と FL2VA は別ファイル。R2V ワークフローに FL2VA を指定すると動作しません**

### ダウンロードコマンド（aria2c）

`/runpod-volume/models` がカレントディレクトリとします（URL は `resolve` で直接配信されるため、`aria2c` の分割ダウンロードで高速化できます）。

**必須（R2V 用）— 計約 40GB**

```bash
# 1. Diffusion Model (Ref2VA: R2V用) ~20.9GB
aria2c -x 16 -s 16 -k 1M -d /runpod-volume/models/diffusion_models \
  -o minimax_h3_ref2va_pruned_int8_convrot.safetensors \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"

# 2. Text Encoder (NVFP4 AWQ) ~14.6GB
aria2c -x 16 -s 16 -k 1M -d /runpod-volume/models/text_encoders \
  -o qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"

# 3. Video VAE (fp16)
aria2c -x 16 -s 16 -k 1M -d /runpod-volume/models/vae \
  -o minimax_h3_video_vae_fp16.safetensors \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors"

# 4. Audio VAE (fp32, 音声生成に必須)
aria2c -x 16 -s 16 -k 1M -d /runpod-volume/models/vae \
  -o minimax_h3_audio_vae_fp32.safetensors \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors"
```

**任意（後で I2V / T2V も試す場合）— +約 19.5GB**

```bash
# 5. Diffusion Model (FL2VA: I2V/T2V用。Ref2VAとは別チェックポイント) ~19.5GB
aria2c -x 16 -s 16 -k 1M -d /runpod-volume/models/diffusion_models \
  -o minimax_h3_fl2va_pruned_int8_convrot.safetensors \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"
```

**備考**

- 5 ファイル合計で約 60GB になり、ボリューム容量の確保が必要です
- 中断・再接続時は `-o` 部分を省略した同じコマンドを再実行すると自動レジュームします
- `aria2c` は Pod のイメージに同梱済みです（`Dockerfile` で追加）

## 4. カスタムノード（ComfyUI Manager から導入）

本体の H3 ノード（`MiniMaxH3*`）と EasyCache は **ComfyUI 本体に内蔵**のため追加不要です（EasyCache は `comfy_extras/nodes_easycache.py` の `ModelSamplingEasyCache` 系ノードとして利用可能）。

| ノード | 役割 | 必須度 |
|---|---|---|
| `KJNodes`（kijai/ComfyUI-KJNodes） | **Patch Sage Attention KJ**（SageAttention をローカル適用） | 必須 |
| `ethanfel/ComfyUI-MiniMax-H3-Guide` | 公式ドキュメント参照のプロンプト/素材管理（R2V 用） | 推奨 |
| `ComfyUI-MiniMax-H3-Turbo`（Larryvrh） | Turbo LoRA 用サンプラー。**後から試す想定** | 後で |

- **EasyCache**: ComfyUI に内蔵（`ModelSamplingEasyCache`）。KJ ノードと併用して約3倍の高速化が期待できる（高速化手法の詳細はセクション7参照）
- **H3-Guide**: Manager に無い場合は手動導入:
  ```bash
  cd /runpod-volume/custom_nodes
  git clone https://github.com/ethanfel/ComfyUI-MiniMax-H3-Guide.git
  ```

## 5. 推奨起動オプション（ComfyUI）

`run_pod_rtx5090.sh` に `--pytorch-index <URL>` 以外の引数はすべて ComfyUI の起動フラグとして渡ります。

```bash
bash /tmp/my-scripts/run_pod_rtx5090.sh \
  --use-sage-attention \
  --disable-pinned-memory
```

- **`--highvram` は付けない**: H3 は拡散（~20GB）+ エンコーダ（~15GB）+ VAE（~5GB）を全モデル載せると 32GB を超え、連続実行時に OOM する。`--highvram` を外した自動オフロード運用が安定（実測: 10秒生成が ~120秒で安定動作）

- **`--use-sage-attention`**: 内蔵 SageAttention（約2倍）。KJ ノードの `Patch Sage Attention KJ` と併用する場合は、グローバルとローカルで品質差が出るケースが報告されているため、両方を試してどちらかを選ぶ
- **`--disable-pinned-memory`**: ComfyUI 0.30.x の pinned-memory バグによりモデルロードが極端に遅くなる回避策。解消されれば外してよい（可変長引数で簡単に変更可能）

## 6. 生成時の推奨パラメータ

- **サンプラー/スケジューラ**: `res_multistep` + `simple`、**20 steps がベース**（15以下は質低下、25でやや高質・低速）
- **解像度**: まず **0.4MP（例: 768x512）** のプレビューから。H3 の場合、384p まで動作は可能
- **長編**:
  - 10 秒一発で VRAM ~27GB（5090 では OK）
  - 15秒 / 768p は VRAM 限界近いため、**複数クリップの継続チェーン**（最後フレーム → 次 first_frame）を使う
- **プロンプト**: タイムライン式が有効。`[0s-4s] ... [4s-7s] ... [7s-10s]` のようにビートで刻む（10 秒なら 2〜3ビートが目安）

## 7. 高速化手法（試す順）

| 手段 | 効果 | 導入状況 |
|---|---|---|
| Sage Attention（内蔵 `--use-sage-attention` または KJノード） | 約2倍 | 導入予定（必須） |
| EasyCache（ComfyUI 内蔵 `ModelSamplingEasyCache`） | KJ と併せて約3倍帯域 | 推奨 |
| Turbo LoRA（`drbaph/MiniMax-H3-Turbo-Lora-ComfyUI` 等） | 20→4〜6stepで最短19秒（5090実測） | **後から試行**（品質/audioに注意） |
| Spectrum-MiniMax-H3 | +30% と言われるが動き品質低下報告あり | 見送り |
| FlashAttention-4 | Blackwell 専用だが ComfyUI/vLLM 未統合 | 見送り |
| H3 ネイティブ sparsed attention | 推論実装が未公開 | 見送り |

## 8. モデル置き場の注意（フォルダ対応）

- エンコーダは `models/text_encoders/`、VAE は `models/vae/`、Diffusion は `models/diffusion_models/` と `extra_model_paths.yaml` が対応済み
- 追加で `models/loras/`（Turbo LoRA 用）も利用可能

## 参照リンク

- 公式ドキュメント: https://docs.comfy.org/tutorials/video/minimax/minimax-h3
- ComfyUI Wiki（日本語版含む）: https://comfyui-wiki.com/en/models/minimax
- HF: https://huggingface.co/Comfy-Org/MiniMax-H3