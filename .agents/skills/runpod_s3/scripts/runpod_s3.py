#!/usr/bin/env python3
"""
RunPod S3 操作スクリプト
boto3 を使ってネットワークボリュームを操作します。

使用方法:
  python3 runpod_s3.py ls [path]
  python3 runpod_s3.py cp <src> <dst>
  python3 runpod_s3.py rm <path>
  python3 runpod_s3.py mirror <src_dir> <dst_dir>

パス形式:
  runpod/          → バケットのルート
  runpod/output/   → output/ フォルダ以下
"""

import os
import sys
import boto3
import argparse
import concurrent.futures
from pathlib import Path
from datetime import timezone

# ---------------------
# 設定読み込み
# ---------------------
def load_env(env_path: str):
    """
    .env ファイルを手動パースして os.environ に設定します。
    python-dotenv に依存しないポータブルな実装。
    """
    if not os.path.exists(env_path):
        return
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            val = val.strip().strip('"').strip("'")
            os.environ.setdefault(key.strip(), val)

# スクリプトの場所から .env のパスを自動解決
SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
load_env(str(SKILL_DIR / ".env"))

RUNPOD_S3_ACCESS_KEY = os.getenv("RUNPOD_S3_ACCESS_KEY")
RUNPOD_S3_SECRET_KEY = os.getenv("RUNPOD_S3_SECRET_KEY")
RUNPOD_S3_ENDPOINT   = os.getenv("RUNPOD_S3_ENDPOINT")
RUNPOD_S3_BUCKET     = os.getenv("RUNPOD_S3_BUCKET")
RUNPOD_S3_REGION     = os.getenv("RUNPOD_S3_REGION")

def validate_env():
    missing = [k for k, v in {
        "RUNPOD_S3_ACCESS_KEY": RUNPOD_S3_ACCESS_KEY,
        "RUNPOD_S3_SECRET_KEY": RUNPOD_S3_SECRET_KEY,
        "RUNPOD_S3_ENDPOINT":   RUNPOD_S3_ENDPOINT,
        "RUNPOD_S3_BUCKET":     RUNPOD_S3_BUCKET,
        "RUNPOD_S3_REGION":     RUNPOD_S3_REGION,
    }.items() if not v]
    if missing:
        print(f"エラー: .env に必要な変数が未設定です: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

def get_client():
    return boto3.client(
        "s3",
        aws_access_key_id=RUNPOD_S3_ACCESS_KEY,
        aws_secret_access_key=RUNPOD_S3_SECRET_KEY,
        endpoint_url=RUNPOD_S3_ENDPOINT,
        region_name=RUNPOD_S3_REGION,
    )

# ---------------------
# パス解決
# ---------------------
def resolve_path(path: str) -> tuple[str, str]:
    """
    'runpod/output/file.png' → (bucket, 'output/file.png')
    'runpod/'               → (bucket, '')
    'runpod'                → (bucket, '')
    """
    path = path.rstrip("/")
    if path == "runpod":
        return RUNPOD_S3_BUCKET, ""
    if path.startswith("runpod/"):
        rest = path[len("runpod/"):]
        # バケット名が含まれている場合は取り除く
        if rest.startswith(RUNPOD_S3_BUCKET + "/"):
            rest = rest[len(RUNPOD_S3_BUCKET) + 1:]
        elif rest == RUNPOD_S3_BUCKET:
            rest = ""
        return RUNPOD_S3_BUCKET, rest
    return RUNPOD_S3_BUCKET, path

def is_remote(path: str) -> bool:
    return path.startswith("runpod")

# ---------------------
# コマンド: ls
# ---------------------
def cmd_ls(s3, path: str, recursive: bool = False):
    bucket, prefix = resolve_path(path)
    if prefix and not prefix.endswith("/"):
        prefix += "/"

    paginator = s3.get_paginator("list_objects_v2")
    kwargs = {"Bucket": bucket, "Prefix": prefix}
    if not recursive:
        kwargs["Delimiter"] = "/"

    found = False
    for page in paginator.paginate(**kwargs):
        # フォルダ（CommonPrefixes）
        for cp in page.get("CommonPrefixes", []):
            found = True
            print(f"               PRE {cp['Prefix']}")

        # ファイル
        for obj in page.get("Contents", []):
            found = True
            key = obj["Key"]
            if prefix and key == prefix:
                continue  # フォルダ自体はスキップ
            size = obj["Size"]
            ts = obj["LastModified"].astimezone().strftime("%Y-%m-%d %H:%M:%S")
            print(f"[{ts}] {size:>12,} {key}")

    if not found:
        print("(空のフォルダ、またはオブジェクトが見つかりませんでした)")

# ---------------------
# コマンド: cp
# ---------------------
def cmd_cp(s3, src: str, dst: str, recursive: bool = False):
    if is_remote(src) and not is_remote(dst):
        # ダウンロード
        bucket, prefix = resolve_path(src)
        if recursive:
            if prefix and not prefix.endswith("/"):
                prefix += "/"
            
            print(f"リモート '{prefix}' からファイルリストを取得中...", flush=True)
            
            keys_to_download = []
            paginator = s3.get_paginator("list_objects_v2")
            # Delimiter='/' を指定して高速に 1 階層分を取得
            for page in paginator.paginate(Bucket=bucket, Prefix=prefix, Delimiter='/'):
                for obj in page.get("Contents", []):
                    key = obj["Key"]
                    if key.endswith("/") or key == prefix:
                        continue
                    keys_to_download.append(key)
            
            if not keys_to_download:
                print("  ダウンロード対象のファイルが見つかりませんでした。", flush=True)
                return
                
            total = len(keys_to_download)
            print(f"計 {total} 件のダウンロードを並列で開始します (Max 8スレッド)...", flush=True)
            
            def download_worker(args_tuple):
                idx, key = args_tuple
                rel = key[len(prefix):] if prefix else key
                local_f = Path(dst) / rel
                try:
                    local_f.parent.mkdir(parents=True, exist_ok=True)
                    s3.download_file(bucket, key, str(local_f))
                    print(f" [{idx}/{total}] 完了: {local_f.name}", flush=True)
                    return True
                except Exception as e:
                    print(f" [{idx}/{total}] エラー ({local_f.name}): {e}", flush=True)
                    return False

            # マルチスレッド並列実行
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
                # インデックスを付けてワーカーに投げる
                tasks = [(i, k) for i, k in enumerate(keys_to_download, 1)]
                list(executor.map(download_worker, tasks))

            print(f"全 {total} 件の処理が完了しました。", flush=True)
        else:
            local_path = Path(dst)
            if local_path.is_dir():
                local_path = local_path / Path(prefix).name
            print(f"ダウンロード: {prefix} → {local_path} ... ", end="", flush=True)
            try:
                s3.download_file(bucket, prefix, str(local_path))
                print("OK", flush=True)
            except Exception as e:
                print(f"ERROR: {e}", flush=True)

    elif not is_remote(src) and is_remote(dst):
        # アップロード
        bucket, prefix = resolve_path(dst)
        src_path = Path(src)
        if recursive and src_path.is_dir():
            for f in src_path.rglob("*"):
                if f.is_file():
                    key = prefix.rstrip("/") + "/" + str(f.relative_to(src_path))
                    print(f"  アップロード: {f} → {key}")
                    s3.upload_file(str(f), bucket, key)
        else:
            key = prefix if not prefix.endswith("/") else prefix + src_path.name
            print(f"  アップロード: {src_path} → {key}")
            s3.upload_file(str(src_path), bucket, key)
    else:
        print("エラー: src か dst のどちらかは 'runpod/' から始まるリモートパスである必要があります。", file=sys.stderr)
        sys.exit(1)

# ---------------------
# コマンド: rm
# ---------------------
def cmd_rm(s3, path: str, recursive: bool = False):
    bucket, prefix = resolve_path(path)
    if recursive:
        if prefix and not prefix.endswith("/"):
            prefix += "/"
        
        print(f"リモート '{prefix}' から削除対象を取得中...", flush=True)
        
        keys_to_delete = []
        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix, Delimiter='/'):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if key == prefix:
                    continue  # フォルダ自体は残す
                keys_to_delete.append(key)
        
        if not keys_to_delete:
            print("  削除対象のファイルが見つかりませんでした。", flush=True)
            return
            
        total = len(keys_to_delete)
        print(f"計 {total} 件の削除を並列で開始します (Max 8スレッド)...", flush=True)
        
        def delete_worker(args_tuple):
            idx, key = args_tuple
            try:
                s3.delete_object(Bucket=bucket, Key=key)
                print(f" [{idx}/{total}] 完了: 削除 {key}", flush=True)
                return True
            except Exception as e:
                print(f" [{idx}/{total}] エラー ({key}): {e}", flush=True)
                return False

        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
            tasks = [(i, k) for i, k in enumerate(keys_to_delete, 1)]
            list(executor.map(delete_worker, tasks))

        print(f"全 {total} 件の削除が完了しました。", flush=True)
    else:
        print(f"  削除: {prefix} ... ", end="", flush=True)
        try:
            s3.delete_object(Bucket=bucket, Key=prefix)
            print("OK", flush=True)
        except Exception as e:
            print(f"ERROR: {e}", flush=True)

# ---------------------
# コマンド: mirror (sync-like)
# ---------------------
def cmd_mirror(s3, src: str, dst: str):
    """
    ローカル → リモート の同期をシミュレート。
    リモート側に存在しないファイル、またはローカルの方が新しいファイルをアップロードします。
    """
    if not is_remote(dst):
        print("エラー: mirror のコピー先は 'runpod/' から始まるリモートパスである必要があります。", file=sys.stderr)
        sys.exit(1)

    bucket, prefix = resolve_path(dst)
    src_path = Path(src)

    if not src_path.is_dir():
        print(f"エラー: ソース '{src}' はディレクトリではありません。", file=sys.stderr)
        sys.exit(1)

    # リモートの状態を取得
    remote_files = {}
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix.rstrip("/") + "/"):
        for obj in page.get("Contents", []):
            rel_key = obj["Key"][len(prefix.rstrip("/")) + 1:]
            remote_files[rel_key] = obj["LastModified"].replace(tzinfo=timezone.utc)

    uploaded = 0
    for f in src_path.rglob("*"):
        if not f.is_file():
            continue
        rel = str(f.relative_to(src_path))
        key = prefix.rstrip("/") + "/" + rel

        should_upload = rel not in remote_files
        if not should_upload:
            local_mtime = f.stat().st_mtime
            import datetime
            remote_mtime = remote_files[rel].timestamp()
            should_upload = local_mtime > remote_mtime

        if should_upload:
            print(f"  アップロード: {f} → {key}")
            s3.upload_file(str(f), bucket, key)
            uploaded += 1

    print(f"ミラー完了: {uploaded} 件アップロードしました。")

# ---------------------
# メイン
# ---------------------
def main():
    validate_env()
    s3 = get_client()

    parser = argparse.ArgumentParser(
        description="RunPod S3 操作ツール（aws-cli 不要）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用例:
  runpod_s3.py ls runpod/              # バケットルートの一覧
  runpod_s3.py ls runpod/output/       # output/ の一覧
  runpod_s3.py ls -r runpod/output/     # output/ を再帰的に一覧
  runpod_s3.py cp runpod/output/a.png ./  # ダウンロード
  runpod_s3.py cp ./img.png runpod/output/ # アップロード
  runpod_s3.py cp -r runpod/output/ ./output/ # フォルダごとダウンロード
  runpod_s3.py rm runpod/output/old.png   # 削除
  runpod_s3.py rm -r runpod/output/dir/    # フォルダごと削除
  runpod_s3.py mirror ./data/ runpod/output/ # ローカル→リモートの同期
"""
    )
    sub = parser.add_subparsers(dest="command")

    # ls
    ls_p = sub.add_parser("ls", help="一覧表示")
    ls_p.add_argument("path", help="リモートパス (例: runpod/output/)")
    ls_p.add_argument("-r", "--recursive", action="store_true", help="再帰的に表示")

    # cp
    cp_p = sub.add_parser("cp", help="コピー（アップロード/ダウンロード）")
    cp_p.add_argument("src", help="コピー元")
    cp_p.add_argument("dst", help="コピー先")
    cp_p.add_argument("-r", "--recursive", action="store_true", help="再帰的にコピー")

    # rm
    rm_p = sub.add_parser("rm", help="削除")
    rm_p.add_argument("path", help="削除するリモートパス")
    rm_p.add_argument("-r", "--recursive", action="store_true", help="再帰的に削除")

    # mirror
    mirror_p = sub.add_parser("mirror", help="ローカル→リモートの差分同期")
    mirror_p.add_argument("src", help="ローカルのソースディレクトリ")
    mirror_p.add_argument("dst", help="リモートの宛先 (例: runpod/output/)")

    args = parser.parse_args()

    if args.command == "ls":
        cmd_ls(s3, args.path, args.recursive)
    elif args.command == "cp":
        cmd_cp(s3, args.src, args.dst, args.recursive)
    elif args.command == "rm":
        cmd_rm(s3, args.path, args.recursive)
    elif args.command == "mirror":
        cmd_mirror(s3, args.src, args.dst)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
