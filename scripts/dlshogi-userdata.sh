#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive


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




# --- dlshogi のビルド ---
# export PATH=/usr/local/cuda/bin:$PATH
# export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}

# WORKDIR=/opt/DeepLearningShogi
# if [ ! -d "$WORKDIR/.git" ]; then
#   git clone https://github.com/TadaoYamaoka/DeepLearningShogi.git "$WORKDIR"
# fi
# cd "$WORKDIR/usi"
# make -j"$(nproc)"

# chown -R ubuntu:ubuntu "$WORKDIR" || true
