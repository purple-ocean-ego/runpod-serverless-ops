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

利用する環境（通常の「Pod」か「Serverless」か）に合わせて、RunPodテンプレートの **「Docker Command（Container Start Command）」** に以下のいずれかのコマンドを1行で指定します。

### 🅰️ 通常のPod用コマンド（GUI操作・デバッグ用）
```bash
bash -c '
# 1. 古いスクリプトを削除して初期化
rm -rf /tmp/my-scripts

# 2. 運用スクリプトを最新の状態でクローン (ネットワーク安定まで最大1分間リトライ)
MAX_RETRIES=6
RETRY_INTERVAL=10
for ((i=1; i<=MAX_RETRIES; i++)); do
    echo "Cloning repository (Attempt $i/$MAX_RETRIES)..."
    if git clone https://github.com/purple-ocean-ego/runpod-serverless-ops.git /tmp/my-scripts; then
        echo "Successfully cloned repository."
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo "Failed to clone repository after $MAX_RETRIES attempts."
        exit 1
    fi
    echo "Clone failed. Retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

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

### 🅱️ Serverless用コマンド（API運用専用）
Serverless Endpointを作成する際の設定です。GUI(ポート8188)やSSHは利用できず、APIリクエストのみを処理し自動スケールします。

```bash
bash -c '
# 1. 古いスクリプトを削除して初期化
rm -rf /tmp/my-scripts

# 2. 運用スクリプトを最新の状態でクローン (ネットワーク安定まで最大1分間リトライ)
MAX_RETRIES=6
RETRY_INTERVAL=10
for ((i=1; i<=MAX_RETRIES; i++)); do
    echo "Cloning repository (Attempt $i/$MAX_RETRIES)..."
    if git clone https://github.com/purple-ocean-ego/runpod-serverless-ops.git /tmp/my-scripts; then
        echo "Successfully cloned repository."
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo "Failed to clone repository after $MAX_RETRIES attempts."
        exit 1
    fi
    echo "Clone failed. Retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

# 3. 実行権限を付与
chmod +x /tmp/my-scripts/*.sh

# 4. GitHub等へのSSH接続をセットアップ（環境変数がない場合は自動スキップ）
bash /tmp/my-scripts/setup_github_ssh.sh

# 5. 排他ロック制御付きでServerlessハンドラを構築・起動・待機
bash /tmp/my-scripts/run_serverless.sh
'
```

### 👆 この構成が実現する革新的な「ハイブリッド運用」
Pod（GUI/開発用）と Serverless（API/本番用）を、**同じ資産（コンテナ、リポジトリ、ネットワークボリューム）**でシームレスに切り替え可能です。

1.  **[同一コンテナ]**: どちらの起動モードでも**完全に同じDockerイメージ**を使用します。環境ごとにイメージをビルドし直す必要はありません。
2.  **[同一リポジトリ]**: 起動時にGitHubから**最新の運用スクリプト群を `/tmp` に使い捨て取得**します。コード修正はGitにプッシュするだけで、両方の環境に即座に反映されます。
3.  **[同一ネットワークボリューム]**: `/runpod-volume` を共有するため、Podで構築した`venv`や追加した`Custom Nodes`、ダウンロードした`Models`が、**そのままServerless環境で即座に利用可能**です。
4.  **[シームレスな切替]**: RunPodの「Docker Command」を1行書き換えるだけで、同一の資産（モデルや設定）を維持したまま、開発・デバッグ用(Pod)と本番・自動スケール用(Serverless)を自由に行き来できます。


---

## 🛠 CI/CD (DockerHub 自動化設定)
本リポジトリには、GitHub Actions を利用した DockerHub への自動ビルド・プッシュ設定が含まれています。

### 設定方法
GitHub リポジトリの **Settings > Secrets and variables > Actions** にて、以下の2つの Repository secrets を登録してください。

1.  **`DOCKERHUB_USERNAME`**: DockerHub のユーザー名
2.  **`DOCKERHUB_TOKEN`**: DockerHub の [Access Token](https://docs.docker.com/docker-hub/access-tokens/)（パスワードではなくトークンを推奨）

これらを登録すると、`main` ブランチへのプッシュ時に自動的にイメージ `${DOCKERHUB_USERNAME}/runpod-serverless-ops:latest` がビルドされ、DockerHub へアップロードされます。

また、Git でタグ（例: `v3.0.0`）を付けてプッシュすると、セマンティックバージョニング形式（`3.0.0`, `3.0`, `3`）でもイメージが自動作成・プッシュされます。ビルドごとの一意な Git SHA もタグとして付与されます。


---


## 🏗 パッケージ管理と安定性（uv 採用）

本システムのパッケージ管理には、超高速な Rust 製ツール **`uv`** を全面的に採用しています。

*   **起動の高速化**: 従来の `pip` に比べてパッケージの解決・インストールが数倍〜数十倍高速です。
*   **依存関係の不整合防止 (Protection)**: 
    *   起動時にベース環境の「正しいバージョン（PyTorch 等）」を `constraints.txt` に記録します。
    *   **ComfyUI-Manager** 等が自動でライブラリをインストールしようとしても、環境変数 `UV_PIP_CONSTRAINTS` を通じて強制的にバージョンを固定し、環境破壊（PyTorch の上書き等）を未然に防ぎます。
*   **自動修復機能**: 起動時に PyTorch のインポートチェックを行い、環境が壊れている場合は自動的に正しいバージョンを再インストールして復旧させます。

---

## ⚠️ 運用上の注意点
*   **環境変数について**：GitHub秘密鍵を扱う場合、RunPod側テンプレートの環境変数に指定キー（`GITHUB_SSH_KEY` または `GITHUB_SSH_KEY_B64`）が正しく登録されている必要があります。登録されていない場合は自動的にスキップされます。
*   **初期コールドスタートの待機時間**：真っ新な空のネットワークボリューム（`/runpod-volume`）に初めてマウントした際は、Pythonパッケージの数百MBのダウンロードやGitのCloneなどが新規に行われるため起動に数分かかります。2回目（ウォームスタート等）以降は `uv` のキャッシュや `venv` が活用されるため、一瞬で起動します。

