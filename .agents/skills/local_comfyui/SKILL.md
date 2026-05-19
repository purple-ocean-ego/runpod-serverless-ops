---
name: ComfyUI ローカル開発環境構築
description: NVIDIA GTX 1660 / Turing 向けに最適化された、完全にサンドボックス化されたローカル Docker ComfyUI 開発環境の構築と起動管理を行います。
---
# ComfyUI ローカル開発環境構築スキル

このスキルは、Zorin OS 18.1 (Ubuntu 24.04) などのホスト環境を一切汚さずに、NVIDIA GTX 1660 GPU の能力を最大限引き出したローカル ComfyUI 開発・検証環境を Docker 上に自動構築し、管理するためのエージェント/開発者向けツールセットです。

---

## ⚡ クイックスタート (QuickStart)

エージェントおよび開発者は、プロジェクトのルートディレクトリで以下の単一のコマンドを実行するだけで、環境ディレクトリの作成、Dockerイメージのビルド、コンテナの起動、および必要なすべての初期セットアップを全自動で実行できます。

```bash
bash .agents/skills/local_comfyui/scripts/run_local.sh
```

### 停止と再起動の操作
コンテナが一度作成された後は、以下の標準的な Docker コマンドで簡単に操作できます：

```bash
# 一時停止
docker stop comfyui-local-dev

# 再起動
docker start comfyui-local-dev

# 起動ログ（画像生成の進捗など）の確認
docker logs -f comfyui-local-dev
```

---

## 📂 スキル構成ファイル (サイドカーファイル一覧)

本スキルは、以下の完全にカプセル化された「サイドカーファイル」によって構成されています。リンクをクリックして各ファイルを開くことができます：

* **リファレンスドキュメント (Philosophy & Gotchas)**:
  * [README.md](/.agents/skills/local_comfyui/references/README.md) - GTX 1660 特有のVRAM最適化設計哲学、`safe.directory` 対策などのトラブル解決ノウハウ。
* **コンテナ起動スクリプト (Host Runner)**:
  * [run_local.sh](/.agents/skills/local_comfyui/scripts/run_local.sh) - ホスト側で動作し、ディレクトリ準備・イメージビルド・マウント起動を実行するマスターランチャー。
* **ビルド定義ファイル (Dockerfile)**:
  * [Dockerfile.local](/.agents/skills/local_comfyui/scripts/Dockerfile.local) - CUDA 12.6, cuDNN, PyTorch 2.12 をキャッシュ焼き込みしたローカル検証専用コンテナイメージ定義。
* **コンテナ初期化定義 (Guest Bootstrapper)**:
  * [setup_local.sh](/.agents/skills/local_comfyui/scripts/setup_local.sh) - コンテナ内での Git 初期セットアップ、カスタムノード依存関係の `uv` 高速解決、サーバー起動を実行するエントリーポイント。
* **モデルディレクトリ定義 (YAML)**:
  * [extra_model_paths_local.yaml](/.agents/skills/local_comfyui/scripts/extra_model_paths_local.yaml) - コンテナ内の `/workspace/models` ディレクトリ群を ComfyUI に認識させるための構成定義。

---

## 💡 使用方法とノウハウ

### 1. モデルファイル (Checkpoints/LoRAs) の配置
ホスト側の `$HOME/comfyui-local/models/` 以下にある対応フォルダ（例: `checkpoints/` や `loras/`）にダウンロードしたファイルを直接配置してください。配置後、ComfyUI の WebUI 上で **「Refresh」** を押すだけで即座にモデルがロード可能になります。

### 2. カスタムノードの追加と自動パッケージ解決
ホスト側の `$HOME/comfyui-local/custom_nodes/` に移動し、追加したいノードを `git clone` してください。
クローン後、コンテナを再起動（`docker restart comfyui-local-dev`）するだけで、エントリーポイントスクリプトが新規ノードの `requirements.txt` を自動検知し、`uv` を使って不足している Python パッケージをシステム環境に自動で爆速追加します。
