---
name: RunPod ファイルクリーンアップ
description: /runpod-volume/output にあるファイルを100枚ずつアーカイブして、Windows にダウンロード・削除します。
---
# RunPod ファイルクリーンアップ

このスキルは、リモートの RunPod インスタンスからファイルを一括アーカイブし、ローカルにダウンロードしてスペースをクリーンアップするプロセスを自動化します。

## 主な機能
- 100 ファイル単位でタイムスタンプ付きの `.tar.gz` にアーカイブします。
- アーカイブが成功した場合のみ、元のソースファイルを削除します。
- **Windows デスクトップ**の `runpod_output` フォルダ内へダウンロードし、自動で解凍します。
- 解凍成功後、ローカルとリモート両方の不要なアーカイブを削除します。

## 前提条件
- `~/.ssh/config` に RunPod への SSH 接続設定が必要です（例: `your-runpod-host`）。

## 使い方
引数に SSH ホスト名と Windows ユーザー名を渡して実行してください：
```bash
# 直接引数を渡す場合
bash .antigravity/skills/runpod_cleanup/scripts/manager.sh <SSH_HOST> <WIN_USER>

# 例:
bash .antigravity/skills/runpod_cleanup/scripts/manager.sh your-runpod-host your-windows-name
```

または、環境変数を設定して引数なしで実行することも可能です：
```bash
export RUNPOD_SSH_HOST="your-runpod-host"
export WINDOWS_USER="your-windows-name"
bash .antigravity/skills/runpod_cleanup/scripts/manager.sh
```

## 構成
- `scripts/remote_cleanup.sh`: RunPod 側で実行されます。
- `scripts/manager.sh`: WSL 側のオーケストレーターです。
