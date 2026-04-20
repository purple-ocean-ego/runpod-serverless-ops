FROM runpod/base:1.0.3-cuda1290-ubuntu2404

# runpod/base に含まれないツールのみ追加
# (curl, git, zstd, ffmpeg, libgl1, libglib2.0-0, unzip, htop, tmux, jq,
#  nginx, openssh-server, Python 3.9-3.13, uv, pip は runpod/base に同梱済み)
RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 nvtop rclone gh \
    && rm -rf /var/lib/apt/lists/*

# TTS(Text-to-Speech)機能などの音声処理のために SoX を追加 (キャッシュ活用のための分離追記)
RUN apt-get update && apt-get install -y --no-install-recommends \
    sox libsox-dev \
    && rm -rf /var/lib/apt/lists/*