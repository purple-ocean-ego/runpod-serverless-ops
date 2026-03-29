---
name: ローカル画像リネーマー
description: ローカルフォルダ内のすべての画像を、連番の4桁形式（0001, 0002, ...）にリネームします。
---
# ローカル画像リネーマー

このスキルは、手動で選別した画像ファイルを整列させ、綺麗な連番形式にリネームして整理するのに役立ちます。

## 特徴
- 画像を `0001.ext`, `0002.ext` などの形式にリネームします。
- `.png`, `.jpg`, `.jpeg`, `.webp` に対応しています。
- 自然なソート順（1, 2, 11...）を維持してリネームします。
- 2段階のリネーム処理により、ファイル名の間での衝突（上書き）を安全に回避します。

## 使い方
選別した画像が入っているフォルダのパスを指定して実行してください：
```bash
bash .antigravity/skills/local_renamer/scripts/rename_all.sh <FOLDER_PATH>
```

実行例（Windows デスクトップのフォルダの場合）:
```bash
bash .antigravity/skills/local_renamer/scripts/rename_all.sh /mnt/c/Users/your-windows-name/Desktop/runpod_output/20260329_123456
```

## 注意事項
連続した番号にするため、実行前にあらかじめ不要なファイルを手動で削除しておくことをお勧めします。
