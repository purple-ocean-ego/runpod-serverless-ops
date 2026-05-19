# ComfyUI ローカル開発環境 設計リファレンス (For Humans & AI Agents)

本ドキュメントは、NVIDIA GTX 1660 (VRAM 6GB / Compute Capability 7.5) に最適化された ComfyUI ローカル Docker 開発環境の設計哲学、アーキテクチャ、制約条件、および運用ノウハウをまとめたものです。

人間だけでなく、将来的にこのプロジェクトを引き継ぐAIエージェントが、**「なぜこの設計になっているのか」「何に気をつけるべきか」**を即座に100%理解し、保守・拡張できるように記述されています。

---

## 🎨 1. 設計の背景と哲学

### 🚀 目的と方針
本ローカル環境は、本番環境である **RunPod Serverless 運用環境** と高い対称性を維持しつつも、ホストの Zorin OS 18.1（Ubuntu 24.04 ベース）環境を一切汚さずに安全にローカル検証を行うことを目的としています。
- **完全なコンテナ内分離**: ホスト側にはDockerとNVIDIA Container Toolkit以外一切の依存（Python仮想環境やCUDAツールキットなど）を求めず、ディレクトリごと消去するだけで完全に跡形もなくリセットできるクリーンさを重視しています。
- **データ永続化とリポジトリ保護**: 大容量のモデル（Checkpoints/LoRAsなど）、生成画像（input/output）、ComfyUIコード本体は、Git管理されている本プロジェクトのコードベースから完全に隔離し、ホスト側の `$HOME/comfyui-local/` に一括永続化します。これにより、ネストされたGitリポジトリの問題や、誤って巨大なモデルファイルをコミットする事故を構造的に防いでいます。

---

## 🏎️ 2. GPU/VRAM 最適化設計 (GTX 1660 向け)

GTX 1660 は Turing 世代の GPU であり、VRAM容量は **6GB (5744 MB)**、CUDA Compute Capability は **7.5** です。このハードウェア制約をクリアするため、以下の最適化を適用しています。

| 最適化項目 | 採用した解決策 | 背景・理由 |
| :--- | :--- | :--- |
| **起動フラグ** | `--lowvram` 固定 | 6GB VRAM で Stable Diffusion や Flux などのモデルを OOM (OutOfMemory) にならずに動作させるため、モデル重みを必要時にシステムRAMから逐次VRAMへ転送する仕組み。 |
| **メモリアロケータ** | `cudaMallocAsync` | PyTorch 2.0+ において、VRAMメモリ割り当てによるオーバーヘッドと断片化を低減し、生成速度と安定性を向上させる設定。 |
| **高速化ライブラリの排除** | FlashAttention / SageAttention の完全排除 | これらは Compute Capability **8.0 以上** (Ampere以降) を厳格に要求します。GTX 1660 (CC 7.5) では動作せず、ビルド時にエラーとなるか無駄な長時間のコンパイルが発生するため、明示的にインストール対象から除外しています。 |

---

## 🛡️ 3. 実装上の技術的罠 (Gotchas) と対策

エージェントや開発者が環境を再構築・修復する際に、最も陥りやすいエラーとその解決策です。

### 🚨 1. ホストマウントでの Git 所有者不一致エラー (`dubious ownership`)
* **現象**: ホスト上のディレクトリ（`dev` ユーザー、UID 1000）を Docker 内部の `/workspace` にマウントし、コンテナ内（`root` ユーザー）で `git` を操作しようとすると、Git のセキュリティ機能（PEP 668 に似た防御）が働き `fatal: detected dubious ownership in repository at '/workspace/ComfyUI'` となり処理が異常終了します。
* **解決策**: スコープを安全に限定しつつ、コンテナ起動初期化スクリプトの先頭で `git config --global --add safe.directory "*"` を実行し、マウントされたディレクトリへの Git 操作を許可しています。

### 🚨 2. Python 外部管理環境エラー (PEP 668)
* **現象**: Ubuntu 24.04 ベースのイメージでシステム Python 環境に対し `uv pip install` を実行しようとすると、システム環境の破壊を防ぐために pip/uv が書き込みを拒否します。
* **解決策**: 環境変数 `ENV UV_BREAK_SYSTEM_PACKAGES=1` およびスクリプト内の `export UV_BREAK_SYSTEM_PACKAGES=1` を宣言することで、使い捨てのコンテナ環境内において安全かつ最速でパッケージをインストールできるようにバイパスしています。

### 🚨 3. Docker ビルド時の DNS 解決エラー
* **現象**: Zorin OS 18.1 (systemd-resolved) などのホスト環境において、Docker ビルド中に `apt-get update` が `archive.ubuntu.com` の名前解決に失敗するネットワークのバグが発生します。
* **解決策**: ビルドランチャースクリプトで `docker build --network host` フラグを付与し、ビルドコンテナが直接ホストのネットワーク名前空間を共有することで、DNS トラブルを100%回避しています。

---

## 📂 4. ディレクトリ連携マップ

ホスト側とコンテナ内部のファイルシステムは、以下のようにマウント接続されます。

```
ホスト側 (Host PC)                               コンテナ内部 (Docker Container)
~/comfyui-local/
├── ComfyUI/  ==============================>  /workspace/ComfyUI/ (ソースコード実体)
├── models/  ===============================>  /workspace/models/ (大容量モデル格納)
├── custom_nodes/  =========================>  /workspace/custom_nodes/ (カスタムノード)
├── input/  ================================>  /workspace/input/ (入力画像)
└── output/  ===============================>  /workspace/output/ (生成された出力画像)

※設定サイドカー
[Skill]/scripts/extra_model_paths_local.yaml => /workspace/extra_model_paths.yaml (読込専用)
[Skill]/scripts/setup_local.sh ==============> /scripts/setup_local.sh (読込専用)
```

---

## 🧩 5. ComfyUI-Manager を意図的に除外した理由

本ローカル検証環境では、一般的な ComfyUI セットアップで使われる `ComfyUI-Manager` プラグインを**意図的に無効化（排除）**しています。
1. **動作負荷の最小化**: Manager は起動時にすべてのカスタムノードのアップデート・競合チェックを走らせるため、起動が著しく遅くなり、リソースの限られた GTX 1660 環境を圧迫します。
2. **決定論的な依存管理**: AIエージェントや開発者が明示的にマウントされた `custom_nodes/` にノードをクローンするだけで、コンテナ起動時に `uv` が爆速かつ安全に `requirements.txt` を自動解決するため、UI操作による暗黙のパッケージ書き換えによる環境破損を防ぎます。
