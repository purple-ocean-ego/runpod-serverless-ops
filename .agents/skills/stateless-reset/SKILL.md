---
name: stateless-reset
description: 過去のAIの記憶やナレッジデータ（brain, knowledge, conversations）を OS の一時フォルダ（/tmp や %TEMP%）へ退避させ、ステートレスな実行環境をリセット（構築）するスキル。
---

# stateless-reset

このスキルは、以前のセッションやチャット履歴、学習済みのナレッジ（知識アイテム）を OS の一時ディレクトリに退避させることで、AIが過去の文脈を引き継がない「ステートレス」な状態を構築します。
物理的な削除ではなく、OSが管理する一時ディレクトリへ移動させるため、必要であれば一時的に復旧することが可能であり、かつ将来的なディスク容量の圧迫も OS の自動クリーンアップ機能によって解消されます。

## 手順

以下の手順に従って環境を確認し、エージェントの内部記憶フォルダ（`brain/`, `knowledge/`, `conversations/`）のみを退避させます。
`skills/` やグローバル設定は維持されるため、エージェントの機能が損なわれることはありません。

**ステップ 1: 実行環境の判定**
ユーザーのOSルールや現在の仮想環境情報からベースとなるOS（Linux, macOS, Windows）を判定します。

**ステップ 2: 記憶キャッシュを一時ディレクトリへ退避する**
判定した環境に合わせて、以下のいずれかのコマンドを順次実行し、各フォルダをタイムスタンプ付きのサブディレクトリへ移動します。

- **Linux / macOS / WSL / SSH (Bash)**
  ```bash
  # ターゲットフォルダの指定
  TARGET_ROOT="$HOME/.gemini/antigravity"
  # 退避先（システム一時ディレクトリ）の作成
  BACKUP_DIR="/tmp/antigravity_context_$(date +%s)"
  mkdir -p "$BACKUP_DIR"

  # 特定のコンテキストフォルダのみを移動
  for dir in brain knowledge conversations; do
    if [ -d "$TARGET_ROOT/$dir" ]; then
      mv "$TARGET_ROOT/$dir" "$BACKUP_DIR/"
      # 必要に応じて空のディレクトリを再作成
      mkdir -p "$TARGET_ROOT/$dir"
    fi
  done
  ```

- **Windows (PowerShell)**
  ```powershell
  # ターゲットフォルダの指定
  $TargetRoot = "$env:USERPROFILE\.gemini\antigravity"
  # 退避先（システム一時ディレクトリ）の作成
  $Timestamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
  $BackupDir = Join-Path $env:TEMP "antigravity_context_$Timestamp"
  New-Item -ItemType Directory -Force -Path $BackupDir

  # 特定のコンテキストフォルダのみを移動
  foreach ($dir in @("brain", "knowledge", "conversations")) {
      $Source = Join-Path $TargetRoot $dir
      if (Test-Path $Source) {
          Move-Item -Path $Source -Destination $BackupDir -Force
          # 必要に応じて空のディレクトリを再作成
          New-Item -ItemType Directory -Force -Path $Source
      }
  }
  ```

**ステップ 3: 結果をユーザーに報告する**
コマンドの実行が無事終了したら、過去の記憶やナレッジがシステムの一時ディレクトリ（`/tmp` または `%TEMP%`）に安全に退避され、コンテキストのリセットが完了したことをユーザーに報告してください。
報告時には、退避先のパスも伝えると親切です。
