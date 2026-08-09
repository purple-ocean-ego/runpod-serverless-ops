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

`extra_model_paths.yaml` のマップ先に合わせて配置します。

| ファイル | 配置先 | サイズ目安 | 備考 |
|---|---|---|---|
| `minimax_h3_fl2va_pruned_int8_convrot.safetensors` | `models/diffusion_models/` | ~19.5 GB | T2V / I2V 用 |
| `minimax_h3_ref2va_pruned_int8_convrot.safetensors` | `models/diffusion_models/` | ~20.9 GB | **R2V 用（FL2VAとは別チェックポイント）** |
| `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | `models/text_encoders/` | ~14.6 GB | NVFP4 エンコーダ。CLIPLoader の type は `minimax` |
| `minimax_h3_video_vae_fp16.safetensors` | `models/vae/` | — | 必須 |
| `minimax_h3_audio_vae_fp32.safetensors` | `models/vae/` | — | 必須（音声生成に必要） |

- 出典: `Comfy-Org/MiniMax-H3`（Hugging Face）を推奨
- T2V / I2V のみなら FL2VA + エンコーダ + VAE 2点（計 ~42GB）。R2V も使うなら Ref2VA を追加（計 ~63GB）
- 注意: **Ref2VA と FL2VA は別ファイル。R2V ワークフローに FL2VA を指定すると動作しません**

## 4. カスタムノード（ComfyUI Manager から導入）

本体の H3 ノード（`MiniMaxH3*`）は ComfyUI 0.30.0+ に内蔵のため追加不要です。

| ノード | 役割 | 必須度 |
|---|---|---|
| `KJNodes`（kijai/ComfyUI-KJNodes） | **Patch Sage Attention KJ**（SageAttention をローカル適用） | 必須 |
| `ComfyUI-EasyCache` | キャッシュによる高速化（KJ × EasyCache で約3倍） | 推奨 |
| `ethanfel/ComfyUI-MiniMax-H3-Guide` | 公式ドキュメント参照のプロンプト/素材管理（R2V 用） | 推奨 |
| `ComfyUI-MiniMax-H3-Turbo`（Larryvrh） | Turbo LoRA 用サンプラー。**後から試す想定** | 後で |

## 5. 推奨起動オプション（ComfyUI）

`run_pod_rtx5090.sh` に `--pytorch-index <URL>` 以外の引数はすべて ComfyUI の起動フラグとして渡ります。

```bash
bash /tmp/my-scripts/run_pod_rtx5090.sh \
  --use-sage-attention \
  --disable-pinned-memory \
  --highvram
```

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
| EasyCache | KJ と併せて約3倍帯域 | 推奨 |
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