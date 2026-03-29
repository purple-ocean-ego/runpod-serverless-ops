---
name: RunPod S3 操作
description: インスタンスを起動せずに、S3互換APIを通じてRunPodネットワークボリュームのファイルを操作（一覧、コピー、同期、削除）します。
---

# RunPod S3 操作

このスキルは、**Python (`boto3`) とポータブルパッケージマネージャー (`uv`)** を利用して S3 互換プロトコル経由で直接 RunPod ネットワークボリュームと通信します。インスタンス(Pod)の起動状況に関わらず、ファイルのアップロードやダウンロード、削除などの操作が可能です。

システム依存のパッケージインストールを避けるため、プロジェクトローカルの `uv` を介して実行時に一時的に `boto3` を読み込む設計になっています。

## 主な機能
- `ls`: ボリューム内のファイルやディレクトリの一覧表示
- `cp`: ローカルとリモート間の単一ファイル/ディレクトリコピー
- `rm`: ファイルやディレクトリの削除
- `mirror`: ローカルディレクトリの内容をリモートディレクトリへ同期

## 前提条件
1. **`.agents/skills/runpod_s3/.env`** ファイルに、以下の環境変数が設定されていること：
   - `RUNPOD_S3_ACCESS_KEY`
   - `RUNPOD_S3_SECRET_KEY`
   - `RUNPOD_S3_ENDPOINT`
   - `RUNPOD_S3_BUCKET` (ボリュームID = バケット名)
   - `RUNPOD_S3_REGION`

## 使い方（AI エージェント向け）
このスキルの `scripts/runpod_s3.sh` は `uv` と Python スクリプトのラッパーです。最初の実行時に自動的に `uv` バイナリをダウンロードし、コマンドを実行します。

ボリューム内のパスを指定する際は**`runpod/`**から始まるパスを使用してください。バケット名等はスクリプト内で自動補完されます。
（例：`runpod/output/file.png`。`runpod/ボリュームID/output/...` と指定しても自動的に正規化されます。）

### 実行例

#### 1. ファイル一覧の取得
```bash
./.agents/skills/runpod_s3/scripts/runpod_s3.sh ls runpod/output/
# 再帰的に一覧したい場合
./.agents/skills/runpod_s3/scripts/runpod_s3.sh ls -r runpod/output/
```

#### 2. ローカルからRunPodへのアップロード
```bash
./.agents/skills/runpod_s3/scripts/runpod_s3.sh cp file.txt runpod/path/to/dist/
```

#### 3. RunPodからローカルへのダウンロード
```bash
./.agents/skills/runpod_s3/scripts/runpod_s3.sh cp runpod/model.safetensors ./models/
```
※ ディレクトリごとコピーする場合は `cp -r` を使用します。

#### 4. ファイルやディレクトリの削除
```bash
# 単一ファイルの削除
./.agents/skills/runpod_s3/scripts/runpod_s3.sh rm runpod/file.txt

# ディレクトリ以下の全削除
./.agents/skills/runpod_s3/scripts/runpod_s3.sh rm -r runpod/path/to/dir/
```

#### 5. ディレクトリの同期（ミラーリング）
ローカルの内容をリモートに送信し、差分だけをアップロードしたい場合：
```bash
./.agents/skills/runpod_s3/scripts/runpod_s3.sh mirror ./local_output/ runpod/output/
```

## トラブルシューティング
- 実行権限エラーが出る場合は `chmod +x .agents/skills/runpod_s3/scripts/runpod_s3.sh` を実行してください。
- 認証エラーが出る場合は、RunPodダッシュボードから発行した **S3 Access Keys** が `.env` に正しく設定されているか確認してください。
