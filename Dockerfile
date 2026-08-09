# RTX 5090 (Blackwell / sm_120) 対応: CUDA 13.0 のベースイメージを使用
# （PyTorch は setup_utils.sh の PYTORCH_INDEX で cu130 / cu126 を切り替える）
FROM runpod/base:1.1.0-cuda1300-ubuntu2404

# runpod/base に含まれないツールのみ追加
# (curl, git, zstd, ffmpeg, libgl1, libglib2.0-0, unzip, htop, tmux, jq,
#  nginx, openssh-server, Python 3.9-3.13, uv, pip は runpod/base に同梱済み)
# sox: TTS 等の音声処理 / ninja-build: FlashAttention ビルド用（FlashAttention-4 統合後も利用）
RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 nvtop rclone gh \
    sox libsox-dev \
    ninja-build \
    && rm -rf /var/lib/apt/lists/*