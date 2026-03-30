#!/bin/bash
# dlshogi EC2 セットアップスクリプト (UserData)
# TensorRT インストール → TRT 10.x パッチ適用 → ビルド → モデル配置 → シンボリックリンク作成
# 進捗は /var/log/cloud-init-output.log で確認できる。
# ARTIFACTS_BUCKET 環境変数が設定されている場合は S3 キャッシュを利用して高速セットアップする。
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

ENGINE_DIR=/home/ubuntu/engines/dlshogi
WORKDIR=/opt/DeepLearningShogi
ARTIFACTS_BUCKET=${ARTIFACTS_BUCKET:-""}
S3_BINARY_KEY="dlshogi/dlshogi_usi"
S3_MODEL_KEY="dlshogi/model.onnx"
S3_BOOK_KEY="dlshogi/book.bin"

# =====================================================================
# 1. 基本パッケージ
# =====================================================================
apt-get update -qq
apt-get install -y --no-install-recommends \
  git build-essential make g++ clang lld \
  libomp-dev libopenblas-dev \
  ca-certificates curl wget unzip python3

# =====================================================================
# 2. CUDA PATH 永続化（/etc/environment は非インタラクティブ SSH でも読まれる）
# =====================================================================
if grep -q '^PATH=' /etc/environment; then
  sed -i 's|^PATH="\(.*\)"|PATH="/usr/local/cuda/bin:\1"|' /etc/environment
else
  echo 'PATH="/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/environment
fi
echo /usr/local/cuda/lib64 > /etc/ld.so.conf.d/cuda.conf
ldconfig

# =====================================================================
# 3. TensorRT インストール（Deep Learning AMI に NVIDIA apt リポジトリ設定済み）
#    ランタイムライブラリのインストールはキャッシュの有無に関わらず常に実行する
# =====================================================================
apt-get install -y tensorrt

mkdir -p "$ENGINE_DIR"

# =====================================================================
# 4. ビルド済みバイナリを S3 から取得、なければソースからビルド
#    注意: TRT メジャーバージョンが変わった場合はバイナリ互換性がないため
#          S3 キャッシュを手動削除して再デプロイすること
# =====================================================================
BINARY_CACHED=false
if [ -n "$ARTIFACTS_BUCKET" ] && aws s3 ls "s3://$ARTIFACTS_BUCKET/$S3_BINARY_KEY" > /dev/null 2>&1; then
  echo "=== S3 キャッシュからエンジンバイナリをダウンロード ==="
  aws s3 cp "s3://$ARTIFACTS_BUCKET/$S3_BINARY_KEY" "$ENGINE_DIR/dlshogi_usi"
  chmod +x "$ENGINE_DIR/dlshogi_usi"
  chown ubuntu:ubuntu "$ENGINE_DIR/dlshogi_usi"
  BINARY_CACHED=true
fi

if [ "$BINARY_CACHED" = false ]; then
  # =====================================================================
  # 4a. DeepLearningShogi クローン
  # =====================================================================
  [ -d "$WORKDIR/.git" ] || git clone https://github.com/TadaoYamaoka/DeepLearningShogi.git "$WORKDIR"
  chown -R ubuntu:ubuntu "$WORKDIR" || true

  # =====================================================================
  # 4b. TensorRT 10.x 互換パッチ（Python で差分のみ適用）
  # TRT 10 削除 API: setMaxBatchSize, setMaxWorkspaceSize, getBindingDimensions,
  #                  setBindingDimensions, enqueue, -lnvparsers
  # =====================================================================
  python3 << 'PYEOF'
import re, sys

def patch(path, replacements):
    with open(path) as f:
        s = f.read()
    for old, new in replacements:
        if old not in s:
            print(f"WARN: patch target not found in {path}: {repr(old[:60])}", file=sys.stderr)
            continue
        s = s.replace(old, new, 1)
    with open(path, 'w') as f:
        f.write(s)

H = '/opt/DeepLearningShogi/usi/nn_tensorrt.h'
patch(H, [(
    '\tstd::vector<void*> inputBindings;\n\tInferUniquePtr',
    '\tstd::vector<void*> inputBindings;\n#if NV_TENSORRT_MAJOR >= 10\n\tstd::string outputNames[2];\n#endif\n\tInferUniquePtr'
)])

CPP = '/opt/DeepLearningShogi/usi/nn_tensorrt.cpp'
patch(CPP, [
    (
        '\tbuilder->setMaxBatchSize(max_batch_size);\n\tconfig->setMaxWorkspaceSize(64_MiB);',
        '#if NV_TENSORRT_MAJOR < 10\n\tbuilder->setMaxBatchSize(max_batch_size);\n\tconfig->setMaxWorkspaceSize(64_MiB);\n#else\n\tconfig->setMemoryPoolLimit(nvinfer1::MemoryPoolType::kWORKSPACE, 64_MiB);\n#endif'
    ),
    (
        '\tinputDims1 = engine->getBindingDimensions(0);\n\tinputDims2 = engine->getBindingDimensions(1);',
        '#if NV_TENSORRT_MAJOR >= 10\n\tinputDims1 = engine->getTensorShape("input1");\n\tinputDims2 = engine->getTensorShape("input2");\n\toutputNames[0].clear(); outputNames[1].clear();\n\tfor (int i = 0; i < engine->getNbIOTensors(); ++i) {\n\t\tconst char* tname = engine->getIOTensorName(i);\n\t\tif (engine->getTensorIOMode(tname) == nvinfer1::TensorIOMode::kOUTPUT) {\n\t\t\tif (outputNames[0].empty()) outputNames[0] = tname;\n\t\t\telse outputNames[1] = tname;\n\t\t}\n\t}\n#else\n\tinputDims1 = engine->getBindingDimensions(0);\n\tinputDims2 = engine->getBindingDimensions(1);\n#endif'
    ),
    (
        '\tcontext->setBindingDimensions(0, inputDims1);\n\tcontext->setBindingDimensions(1, inputDims2);\n\tconst bool status = context->enqueue(batch_size, inputBindings.data(), cudaStreamPerThread, nullptr);',
        '#if NV_TENSORRT_MAJOR >= 10\n\tcontext->setInputShape("input1", inputDims1);\n\tcontext->setInputShape("input2", inputDims2);\n\tcontext->setTensorAddress("input1", x1_dev);\n\tcontext->setTensorAddress("input2", x2_dev);\n\tcontext->setTensorAddress(outputNames[0].c_str(), y1_dev);\n\tcontext->setTensorAddress(outputNames[1].c_str(), y2_dev);\n\tconst bool status = context->enqueueV3(cudaStreamPerThread);\n#else\n\tcontext->setBindingDimensions(0, inputDims1);\n\tcontext->setBindingDimensions(1, inputDims2);\n\tconst bool status = context->enqueue(batch_size, inputBindings.data(), cudaStreamPerThread, nullptr);\n#endif'
    ),
])
PYEOF

  # Makefile: TRT 10 で削除された -lnvparsers を除去
  sed -i 's/ -lnvparsers//' "$WORKDIR/usi/Makefile"
  chown -R ubuntu:ubuntu "$WORKDIR" || true

  # =====================================================================
  # 4c. ビルド
  # =====================================================================
  cd "$WORKDIR/usi"
  make clean
  make -j"$(nproc)" CC=g++
  cp bin/usi "$ENGINE_DIR/dlshogi_usi"
  chown -R ubuntu:ubuntu "$ENGINE_DIR"

  # =====================================================================
  # 4d. ビルド済みバイナリを S3 にアップロード（次回以降の高速起動用）
  # =====================================================================
  if [ -n "$ARTIFACTS_BUCKET" ]; then
    echo "=== ビルド済みバイナリを S3 にアップロード ==="
    aws s3 cp "$ENGINE_DIR/dlshogi_usi" "s3://$ARTIFACTS_BUCKET/$S3_BINARY_KEY"
  fi
fi

# =====================================================================
# 5. モデルファイル（S3 キャッシュ優先、なければ GitHub からダウンロード）
# =====================================================================
MODEL_URL=https://github.com/TadaoYamaoka/DeepLearningShogi/releases/download/wcwc31/dlshogi_with_gct_wcsc31.zip

MODEL_CACHED=false
if [ -n "$ARTIFACTS_BUCKET" ] && aws s3 ls "s3://$ARTIFACTS_BUCKET/$S3_MODEL_KEY" > /dev/null 2>&1; then
  echo "=== S3 キャッシュからモデルファイルをダウンロード ==="
  aws s3 cp "s3://$ARTIFACTS_BUCKET/$S3_MODEL_KEY" "$ENGINE_DIR/model.onnx"
  aws s3 cp "s3://$ARTIFACTS_BUCKET/$S3_BOOK_KEY"  "$ENGINE_DIR/book.bin"
  chown ubuntu:ubuntu "$ENGINE_DIR/model.onnx" "$ENGINE_DIR/book.bin"
  MODEL_CACHED=true
fi

if [ "$MODEL_CACHED" = false ] && [ ! -f "$ENGINE_DIR/model.onnx" ]; then
  # model-dr2_exhi.zip は ZipCrypto 暗号化で使用不可のため wcwc31 版を使用
  wget -q "$MODEL_URL" -O /tmp/dlshogi_wcwc31.zip
  unzip -o /tmp/dlshogi_wcwc31.zip model-0000225kai.onnx book_model-0000223_225kai_4m.bin -d /tmp/model_extract/
  cp /tmp/model_extract/model-0000225kai.onnx         "$ENGINE_DIR/model.onnx"
  cp /tmp/model_extract/book_model-0000223_225kai_4m.bin "$ENGINE_DIR/book.bin"
  chown ubuntu:ubuntu "$ENGINE_DIR/model.onnx" "$ENGINE_DIR/book.bin"
  rm -rf /tmp/dlshogi_wcwc31.zip /tmp/model_extract/

  if [ -n "$ARTIFACTS_BUCKET" ]; then
    echo "=== モデルファイルを S3 にアップロード ==="
    aws s3 cp "$ENGINE_DIR/model.onnx" "s3://$ARTIFACTS_BUCKET/$S3_MODEL_KEY"
    aws s3 cp "$ENGINE_DIR/book.bin"   "s3://$ARTIFACTS_BUCKET/$S3_BOOK_KEY"
  fi
fi

# =====================================================================
# 6. シンボリックリンク（冪等）
# /usr/local/bin/dlshogi_usi → PATH が通っておりコマンド名だけで起動可能
# ~/model.onnx, ~/book.bin  → SSH 直接実行時の作業ディレクトリ (/home/ubuntu) から参照
# =====================================================================
ln -sf "$ENGINE_DIR/dlshogi_usi" /usr/local/bin/dlshogi_usi
ln -sf "$ENGINE_DIR/model.onnx"  /home/ubuntu/model.onnx
ln -sf "$ENGINE_DIR/book.bin"    /home/ubuntu/book.bin
chown -h ubuntu:ubuntu /home/ubuntu/model.onnx /home/ubuntu/book.bin || true
