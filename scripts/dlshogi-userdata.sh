#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# 前提ライブラリ (Ubuntu 18.04 / g4dn.xlarge / NVIDIA T4)
#   - NVIDIA Driver 530  (cuda-drivers-530, cuda-11-0 に同梱)
#   - CUDA 11.0
#   - cuDNN 8.0
#   - TensorRT 7.1.3.4   (S3 から取得: ${TENSORRT_S3_URI})
# ---------------------------------------------------------------------------

# --- 基本パッケージ ---
apt-get update -qq
apt-get install -y --no-install-recommends \
  git \
  build-essential \
  make \
  g++ \
  ca-certificates \
  curl \
  wget \
  unzip

# --- AWS CLI v2 (TensorRT を S3 から取得するために使用) ---
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/awscli
/tmp/awscli/aws/install
rm -rf /tmp/awscliv2.zip /tmp/awscli

# --- NVIDIA CUDA リポジトリのセットアップ ---
# (以前の実行で残ったエントリを削除してから追加)
rm -f /etc/apt/sources.list.d/cuda*.list /etc/apt/sources.list.d/nvidia*.list
sed -i '/developer.download.nvidia.com/d' /etc/apt/sources.list

wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-keyring_1.0-1_all.deb
dpkg -i cuda-keyring_1.0-1_all.deb
rm cuda-keyring_1.0-1_all.deb
apt-get update -qq

# --- CUDA 11.0 + NVIDIA Driver ---
apt-get install -y --no-install-recommends cuda-11-0

# --- cuDNN 8.0 ---
apt-get install -y --no-install-recommends \
  libcudnn8=8.0.5.39-1+cuda11.0 \
  libcudnn8-dev=8.0.5.39-1+cuda11.0

# --- TensorRT 7.1.3.4 ---
# S3 からダウンロード (EC2 IAM ロールの S3 読み取り権限を使用)
/usr/local/bin/aws s3 cp "${TENSORRT_S3_URI}" /tmp/TensorRT.tar.gz
tar xf /tmp/TensorRT.tar.gz -C /opt/
rm /tmp/TensorRT.tar.gz

# Makefile が参照する -I/usr/local/cuda/include, -L/usr/local/cuda/lib64 に配置
cp /opt/TensorRT-7.1.3.4/include/* /usr/local/cuda/include/
cp /opt/TensorRT-7.1.3.4/lib/*.so* /usr/local/cuda/lib64/
ldconfig

# --- dlshogi のビルド ---
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}

WORKDIR=/opt/DeepLearningShogi
git clone https://github.com/TadaoYamaoka/DeepLearningShogi.git "$WORKDIR"
cd "$WORKDIR/usi"
make

chown -R ubuntu:ubuntu "$WORKDIR" || true
