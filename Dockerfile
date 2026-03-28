FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# システムのアップデートと、GPU運用・AIタスクに必須・便利なツール群の導入
RUN apt-get update && apt-get install -y \
    curl git zstd aria2 libgl1-mesa-glx libglib2.0-0 ffmpeg unzip \
    htop nvtop tmux jq rclone gh \
    && rm -rf /var/lib/apt/lists/*