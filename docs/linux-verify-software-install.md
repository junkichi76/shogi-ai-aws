# 必要ソフトウェアのインストール確認手順

## 目的

[DeepLearningShogi wiki](https://github.com/TadaoYamaoka/DeepLearningShogi/wiki) に記載されている必要ソフトウェアが、正しくインストール・認識されているかを確認するための手順書です。

## 確認対象ソフトウェア一覧

| ソフトウェア | wikiの推奨バージョン | 確認コマンド |
|---|---|---|
| NVIDIA ドライバ | 最新推奨 | `nvidia-smi` |
| CUDA | 10.2以上（10.2または12.x推奨） | `nvcc --version` |
| cuDNN | 7.6以上 | ヘッダファイル確認 |
| TensorRT | 7以上 | `ldconfig -p \| grep nvinfer` |
| g++ | ビルド用 | `g++ --version` |
| clang++ | ふかうら王ビルド用 | `clang++ --version` |
| Python 3 | 学習利用時 | `python3 --version` |

---

## 1. NVIDIAドライバ

GPUがOSから認識されているかを確認します。

```bash
nvidia-smi
```

正常時の出力例：

```
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 535.xx.xx    Driver Version: 535.xx.xx    CUDA Version: 12.2    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
...
```

**NG例・対処：**

- `nvidia-smi: command not found` → NVIDIAドライバ未導入
- `Failed to initialize NVML` → カーネルモジュールが未ロード（再起動を試みる）

---

## 2. CUDA Toolkit

CUDAコンパイラ `nvcc` が見えるかを確認します。

```bash
nvcc --version
```

正常時の出力例：

```
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2023 NVIDIA Corporation
Built on ...
Cuda compilation tools, release 12.2, V12.2.91
```

**`nvcc` が見つからない場合：**

```bash
# PATHを確認
echo $PATH | tr ':' '\n' | grep cuda

# 一時的に通す
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
```

CUDAライブラリが見えるかも確認します。

```bash
ldconfig -p | grep libcuda
```

`libcuda.so` が表示されれば認識されています。

---

## 3. cuDNN

cuDNNのヘッダファイルが存在するか確認します。

```bash
find /usr/local/cuda/include /usr /opt -name "cudnn.h" 2>/dev/null
```

バージョンを確認したい場合は、ヘッダから取得できます。

```bash
cat /usr/local/cuda/include/cudnn_version.h 2>/dev/null \
  | grep -E "CUDNN_MAJOR|CUDNN_MINOR|CUDNN_PATCHLEVEL" \
  | head -3
```

または：

```bash
cat /usr/include/cudnn_version.h 2>/dev/null \
  | grep -E "CUDNN_MAJOR|CUDNN_MINOR|CUDNN_PATCHLEVEL" \
  | head -3
```

正常時の出力例（cuDNN 8.x の場合）：

```
#define CUDNN_MAJOR 8
#define CUDNN_MINOR 9
#define CUDNN_PATCHLEVEL 2
```

ライブラリがリンカに見えるかも確認します。

```bash
ldconfig -p | grep libcudnn
```

`libcudnn.so` が表示されれば認識されています。

---

## 4. TensorRT

TensorRTの中核ライブラリ `libnvinfer` がリンカに見えるかを確認します。

```bash
ldconfig -p | grep nvinfer
```

正常時の出力例：

```
        libnvinfer.so.8 (libc6,x86-64) => /usr/lib/x86_64-linux-gnu/libnvinfer.so.8
        libnvinfer_plugin.so.8 (libc6,x86-64) => /usr/lib/x86_64-linux-gnu/libnvinfer_plugin.so.8
```

バージョンを確認したい場合：

```bash
find /usr /opt -name "NvInferVersion.h" 2>/dev/null | head -3
cat $(find /usr /opt -name "NvInferVersion.h" 2>/dev/null | head -1) \
  | grep -E "NV_TENSORRT_MAJOR|NV_TENSORRT_MINOR|NV_TENSORRT_PATCH" 2>/dev/null
```

**何も出ない場合：**

- TensorRTが未導入、またはインストール先がリンカに登録されていない
- `/etc/ld.so.conf.d/` にTensorRTのlibパスを追加して `sudo ldconfig` を実行する

---

## 5. ビルドツール

### g++

```bash
g++ --version
```

正常時の出力例：

```
g++ (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
```

### clang++

ふかうら王のビルドは `clang++` を使用します。

```bash
clang++ --version
```

正常時の出力例：

```
Ubuntu clang version 14.0.0-1ubuntu1
```

`clang++` が見つからない場合：

```bash
sudo apt install -y clang lld
```

### make / cmake

```bash
make --version
cmake --version 2>/dev/null || echo "cmake not installed"
```

---

## 6. Python 3（学習利用時）

学習・データ変換にPythonを使う場合に確認します。

```bash
python3 --version
pip3 --version
```

PyTorchが入っているか確認：

```bash
python3 -c "import torch; print(torch.__version__); print('CUDA available:', torch.cuda.is_available())"
```

正常時の出力例：

```
2.1.0+cu121
CUDA available: True
```

---

## 7. ONNX Runtime（ORT-CPU版 使用時）

ORT-CPU版のふかうら王を使う場合、`libonnxruntime` がリンカに見えるかを確認します。

```bash
ldconfig -p | grep onnxruntime
```

正常時の出力例：

```
        libonnxruntime.so.1.11.1 (libc6,x86-64) => /home/ubuntu/onnxruntime-linux-x64-1.11.1/lib/libonnxruntime.so.1.11.1
```

何も出ない場合は、以下で登録します。

```bash
# ONNX Runtimeを展開したパスに合わせて変更
echo "$HOME/onnxruntime-linux-x64-1.11.1/lib" | sudo tee /etc/ld.so.conf.d/onnxruntime.conf
sudo ldconfig
```

---

## 8. ふかうら王・dlshogi の動作確認

### ふかうら王（USI応答確認）

```bash
cd ~/engines/fukauraou
echo -e "usi\nquit" | ./FukauraOuLinux
```

`usiok` が返れば最低限の起動は成功しています。

`isready` まで確認する場合：

```bash
echo -e "usi\nisready\nquit" | ./FukauraOuLinux
```

`readyok` が返れば、モデル読み込みを含めた初期化が完了しています。

### dlshogi（USI応答確認）

```bash
cd ~/engines/dlshogi
echo -e "usi\nquit" | ./dlshogi_usi
```

`usiok` が返れば起動は成功しています。

`isready` まで確認する場合（TensorRTエンジン生成が走るため初回は時間がかかります）：

```bash
echo -e "usi\nisready\nquit" | ./dlshogi_usi
```

`readyok` が返れば正常です。

---

## 9. 一括確認スクリプト

上記の確認をまとめて実行したい場合は、以下のスクリプトを使います。

```bash
#!/usr/bin/env bash
set -euo pipefail

ok()  { echo "[OK]  $1"; }
ng()  { echo "[NG]  $1"; }
skip(){ echo "[--]  $1 (確認対象外)"; }

echo "=== NVIDIAドライバ ==="
if nvidia-smi > /dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
  ok "nvidia-smi"
else
  ng "nvidia-smi が失敗 (ドライバ未導入またはカーネルモジュール未ロード)"
fi

echo ""
echo "=== CUDA ==="
if command -v nvcc > /dev/null 2>&1; then
  nvcc --version | grep "release"
  ok "nvcc"
else
  ng "nvcc が見つからない (PATH未設定またはCUDA Toolkit未導入)"
fi

echo ""
echo "=== cuDNN ==="
CUDNN_H=$(find /usr/local/cuda/include /usr/include -name "cudnn_version.h" 2>/dev/null | head -1)
if [ -n "$CUDNN_H" ]; then
  MAJOR=$(grep CUDNN_MAJOR "$CUDNN_H" | head -1 | awk '{print $3}')
  MINOR=$(grep CUDNN_MINOR "$CUDNN_H" | head -1 | awk '{print $3}')
  ok "cuDNN ${MAJOR}.${MINOR} (${CUDNN_H})"
else
  ng "cudnn_version.h が見つからない"
fi

echo ""
echo "=== TensorRT ==="
if ldconfig -p | grep -q libnvinfer; then
  ldconfig -p | grep libnvinfer | head -3
  ok "libnvinfer (TensorRT)"
else
  ng "libnvinfer が見つからない"
fi

echo ""
echo "=== ONNX Runtime ==="
if ldconfig -p | grep -q onnxruntime; then
  ldconfig -p | grep onnxruntime | head -2
  ok "libonnxruntime"
else
  skip "libonnxruntime (ORT-CPU版不使用の場合は問題なし)"
fi

echo ""
echo "=== ビルドツール ==="
for cmd in g++ clang++ make; do
  if command -v "$cmd" > /dev/null 2>&1; then
    ok "$cmd: $($cmd --version | head -1)"
  else
    ng "$cmd が見つからない"
  fi
done

echo ""
echo "=== Python 3 ==="
if command -v python3 > /dev/null 2>&1; then
  ok "python3: $(python3 --version)"
else
  skip "python3 (学習利用しない場合は問題なし)"
fi

echo ""
echo "=== 完了 ==="
```

スクリプトの実行方法：

```bash
bash ~/verify-software.sh
```

---

## 10. 確認チェックリスト

| 確認項目 | コマンド | 期待結果 |
|---|---|---|
| NVIDIAドライバ | `nvidia-smi` | GPU名・ドライババージョンが表示される |
| CUDA | `nvcc --version` | CUDAバージョンが表示される |
| CUDAライブラリ | `ldconfig -p \| grep libcuda` | `libcuda.so` が表示される |
| cuDNN ヘッダ | `find ... -name cudnn_version.h` | ファイルが見つかる |
| cuDNN ライブラリ | `ldconfig -p \| grep libcudnn` | `libcudnn.so` が表示される |
| TensorRT | `ldconfig -p \| grep nvinfer` | `libnvinfer.so` が表示される |
| g++ | `g++ --version` | バージョンが表示される |
| clang++ | `clang++ --version` | バージョンが表示される |
| ふかうら王 USI | `echo -e "usi\nquit" \| ./FukauraOuLinux` | `usiok` が返る |
| dlshogi USI | `echo -e "usi\nquit" \| ./dlshogi_usi` | `usiok` が返る |
| ふかうら王 readyok | `echo -e "usi\nisready\nquit" \| ./FukauraOuLinux` | `readyok` が返る |
| dlshogi readyok | `echo -e "usi\nisready\nquit" \| ./dlshogi_usi` | `readyok` が返る |

---

## 参考

- [DeepLearningShogi wiki](https://github.com/TadaoYamaoka/DeepLearningShogi/wiki)
- [ふかうら王インストール手順 (本リポジトリ)](linux-install-fukauraou-dlshogi.md)
