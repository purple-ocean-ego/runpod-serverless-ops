# ComfyUI コンテナ構築・運用ガイド

本ディレクトリには、RunPod等クラウドGPU環境にデプロイできる、超軽量かつセキュアなComfyUI完全自動構築用の構成ファイル一式が含まれています。

## 🏛 アーキテクチャの基本思想（完全分離型）
この構成では、コンテナのDockerイメージ内にアプリを埋め込むことを完全にやめ、**「OSの必須ツール（`ffmpeg`や`OpenCV`の依存関係など）のみ」**を焼き付けた「ただのPythonが動く箱」にしています。
ComfyUI本体・Python依存ライブラリ・巨大なモデルデータなどはすべて**ネットワークボリューム (`/runpod-volume`)** 上に配置・構築する「分離連携・GitOps運用」となっています。

これにより、以下のような強力なメリットが生まれます。
*   **イメージの超軽量化**：Dockerイメージのビルド時間がわずか数秒になり、保守が極限まで手軽に。
*   **再構築1秒の強み**：ComfyUIが壊れた際、重いDockerコンテナを作り直すことなく、`/runpod-volume/ComfyUI` フォルダを削除してPodを再起動するだけでクリーンインストールが可能。
*   **資産の完全保護**：数GB〜数十GBのモデルファイル（`models`）や生成した画像（`output`）は、独立した安全なディレクトリに隔離されているため、ComfyUI本体を何度消しても資産が1Byteも失われない。

---

## 📜 必要なファイル群とその役割
今後これらのスクリプトはパブリックのGitHubリポジトリで一元管理されることを想定しています。

1.  **`Dockerfile`**
    *   システムツール（`ffmpeg`, `libgl1-mesa-glx` など）の導入に加え、GPU運用・AIタスクで必須の保守ツール群（`nvtop`, `htop`, `tmux`, `rclone`, `jq`, `gh`）のインストールのみを行います。このファイルを使って軽量なベースイメージをビルドし、DockerHub等に紐付けておきます。
2.  **`run_app.sh`**
    *   コンテナ起動時に動作する司令塔。指定のネットワークボリューム配下にComfyUI本体とPython仮想環境 (`venv`) を自動作成・更新して起動します。
    *   壊れがちな「カスタムノード群」だけはあえてComfyUI本体と共に配置し、トラブル時の丸ごと再構築を容易くしています。
3.  **`extra_model_paths.yaml`**
    *   ComfyUIにモデルデータの場所（`/runpod-volume/models`）を教えるマップファイルです。
4.  **`setup_github_ssh.sh`**
    *   コンテナの実行時に、RunPodで裏側から設定された暗号環境変数（秘密鍵等）を読み込み、コンテナのOS内に安全にSSH鍵をセットアップします。

---

## 🚀 【重要】最も強力な起動コマンド（GitOps）
これらの運用スクリプト群を公開GitHubリポジトリ（パブリックリポジトリ）で管理する場合、RunPodテンプレートの **「Docker Command（Container Start Command）」** に以下のコマンドを1行で指定します。

```bash
bash -c '
# 1. 古いスクリプトを削除して初期化
rm -rf /tmp/my-scripts

# 2. 運用スクリプトを最新の状態でクローン
git clone https://github.com/purple-ocean-ego/runpod-serverless-ops.git /tmp/my-scripts

# 3. 実行権限を付与
chmod +x /tmp/my-scripts/*.sh

# 4. GitHub等へのSSH接続をセットアップ（環境変数がない場合は自動スキップ）
bash /tmp/my-scripts/setup_github_ssh.sh

# 5. ComfyUIや関連依存関係の環境構築＆起動
bash /tmp/my-scripts/run_app.sh

# 6. 全て完了した後、RunPodの標準待機プロセスを開始
/start.sh
'
```

### 👆 このコマンドが発生させる劇的な効果
1.  **[取得]**: コンテナ起動時、常にパブリックリポジトリから**最新の運用スクリプト群を `/tmp` に使い捨て取得**します（修正の手間ゼロ）。
2.  **[認証]**: スクリプト内の `setup_github_ssh.sh` が走り、RunPodの秘密の環境変数から安全にSSH鍵を展開・登録します。
3.  **[環境構築]**: バックグラウンドで `run_app.sh` が走り、先ほど構成されたSSH鍵なども利用しながら、必要なもの（ComfyUIやOllama、プライベートなカスタムノード等）を `/runpod-volume` 上へ非同期で構築・起動します。
4.  **[完了と永続化]**: 同時にRunPod標準の公式スクリプト `/start.sh` がフォアグラウンドで立ち上がり、Jupyter等の初期化を行い、Podを恒久的に継続稼働させつつ待機します。

---

## 🛠 CI/CD (DockerHub 自動化設定)
本リポジトリには、GitHub Actions を利用した DockerHub への自動ビルド・プッシュ設定が含まれています。

### 設定方法
GitHub リポジトリの **Settings > Secrets and variables > Actions** にて、以下の2つの Repository secrets を登録してください。

1.  **`DOCKERHUB_USERNAME`**: DockerHub のユーザー名
2.  **`DOCKERHUB_TOKEN`**: DockerHub の [Access Token](https://docs.docker.com/docker-hub/access-tokens/)（パスワードではなくトークンを推奨）

これらを登録すると、`main` ブランチへのプッシュ時に自動的にイメージ `${DOCKERHUB_USERNAME}/runpod-serverless-ops:latest` がビルドされ、DockerHub へアップロードされます。

また、Git でタグ（例: `v1.0.1`）を付けてプッシュすると、セマンティックバージョニング形式（`1.0.1`, `1.0`, `1`）でもイメージが自動作成・プッシュされます。ビルドごとの一意な Git SHA もタグとして付与されます。

---


## ⚠️ 運用上の注意点
*   **環境変数について**：GitHub秘密鍵を扱う場合、RunPod側テンプレートの環境変数に指定キー（`GITHUB_SSH_KEY` または `GITHUB_SSH_KEY_B64`）が正しく登録されている必要があります。登録されていない場合は自動的にスキップされます。
*   **初期コールドスタートの待機時間**：真っ新な空のネットワークボリューム（`/runpod-volume`）に初めてマウントした際は、Pythonパッケージの数百MBのダウンロードやGitのCloneなどが新規に行われるため起動に数分かかります。2回目（ウォームスタート等）以降はvenvなどが既に完成しているため一瞬で起動します。
