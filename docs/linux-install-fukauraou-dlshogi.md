# ふかうら王とdlshogiのLinuxインストール手順

## 目的

Ubuntu系Linux上で、以下を動かせる状態にするための手順書です。

- ふかうら王
- dlshogi

この手順は、将棋GUIに登録するためのUSIエンジン利用を主目的にしています。学習用途で使う場合は、後述のPython環境も追加で構築してください。

## 想定環境

- OS: Ubuntu 20.04 / 22.04 系
- CPU: x86_64
- GPU: NVIDIA GPU推奨
- ドライバ: NVIDIA Driver導入済み

補足:

- dlshogiの公式READMEでは、Linuxのビルド環境として Ubuntu 18.04 LTS / 20.04 LTS、g++、CUDA 12.1、cuDNN 8.9、TensorRT 8.6 が案内されています。
- ふかうら王はGPUなしでも起動自体は可能な系統がありますが、公式Wikiでも GPUなしでは本来の性能が大きく落ちる と案内されています。実運用はGPU前提で考えるのが無難です。

## 公式情報

- dlshogi: https://github.com/TadaoYamaoka/DeepLearningShogi
- ふかうら王: https://github.com/yaneurao/YaneuraOu/wiki/ふかうら王のインストール手順
- ふかうら王ビルド: https://github.com/yaneurao/YaneuraOu/wiki/ふかうら王のビルド手順

## 1. 共通の事前準備

### 1-1. 開発ツールの導入

まずはビルドに必要な基本ツールを入れます。

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  g++ \
  clang \
  lld \
  libomp-dev \
  libopenblas-dev \
  git \
  curl \
  unzip \
  pkg-config \
  python3 \
  python3-pip \
  python3-venv
```

### 1-2. NVIDIAドライバとCUDAの確認

ドライバが正しく入っているか確認します。

```bash
nvidia-smi
```

CUDAコンパイラが見えるか確認します。

```bash
nvcc --version
```

`nvcc` が見つからない場合は、CUDA Toolkitの `bin` がPATHに入っていない可能性があります。典型例は以下です。

```bash
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
```

永続化する場合は `~/.bashrc` または `~/.zshrc` に追記してください。

### 1-3. cuDNN / TensorRT の導入方針

dlshogiとふかうら王は、どちらもTensorRTやcuDNNのバージョン差分で詰まりやすいです。特に両者を同じマシンで共存させる場合は、以下のどちらかに寄せると安定します。

- できるだけ同一世代のCUDA / TensorRT / cuDNNにそろえる
- Dockerで分離する

ソースから直接ビルドする場合は、少なくとも以下が満たされている必要があります。

- CUDAヘッダが `/usr/local/cuda/include` にある
- CUDAライブラリが `/usr/local/cuda/lib64` にある
- TensorRTライブラリが標準のライブラリ検索パス、または `LD_LIBRARY_PATH` から見える

確認例:

```bash
ldconfig -p | grep nvinfer
```

何も出ない場合は、TensorRTの導入先がランタイムリンカに見えていません。

## 2. ふかうら王のインストール

Linuxでは、配布済みのWindows向け実行ファイルをそのまま使うのではなく、基本的にソースからビルドする想定で進めます。

### 2-1. ソース取得

```bash
cd ~
git clone https://github.com/yaneurao/YaneuraOu.git
cd YaneuraOu/source
```

### 2-2. ビルド

公式WikiのUbuntu向け手順では、以下のビルド例が示されています。

```bash
make clean YANEURAOU_EDITION=YANEURAOU_ENGINE_DEEP_TENSOR_RT_UBUNTU
make -j$(nproc) tournament \
  COMPILER=clang++ \
  YANEURAOU_EDITION=YANEURAOU_ENGINE_DEEP_TENSOR_RT_UBUNTU \
  ENGINE_NAME="FukauraOuLinux" \
  TARGET_CPU=AVX2
```

補足:

- `TARGET_CPU=AVX2` は一般的なx86_64向けです
- Ryzen系で最適化を分けたい場合は、環境に応じて `ZEN2` などを検討してください
- `clang++` が見つからない場合は `COMPILER=clang++-14` のように実体に合わせてください

ビルドが成功すると、実行ファイルが生成されます。環境によって出力名は多少異なることがありますが、Wikiの例では `YaneuraOu-by-gcc` が生成される前提になっています。

必要なら配置用ディレクトリを作成します。

```bash
mkdir -p ~/engines/fukauraou/eval
cp ./YaneuraOu-by-gcc ~/engines/fukauraou/FukauraOuLinux
```

### 2-3. モデルファイルの取得と配置

ふかうら王は、dlshogi互換のONNX形式モデルを読み込みます。公式Wikiでは、モデルは `EvalDir` で指定したフォルダに置く前提です。

モデルは dlshogi のリリースページから入手します。

- https://github.com/TadaoYamaoka/DeepLearningShogi/releases

以下は WCSC31版のモデルを使う場合のコマンド例です。

```bash
cd ~
wget https://github.com/TadaoYamaoka/DeepLearningShogi/releases/download/wcwc31/dlshogi_with_gct_wcsc31.zip
unzip dlshogi_with_gct_wcsc31.zip -d dlshogi_wcsc31
```

展開後のフォルダには `model-0000225kai.onnx`、`model-0000226kai.onnx` などのモデルファイルが含まれています。

```
$ ls ~/dlshogi_wcsc31/
model-0000225kai.onnx  model-0000226kai.onnx  book.bin  ...
```

evalフォルダにモデルを配置します。ふかうら王はデフォルトで `eval/model.onnx` というファイル名を探すため、ファイル名を合わせてコピーします。

```bash
mkdir -p ~/engines/fukauraou/eval
cp ~/dlshogi_wcsc31/model-0000225kai.onnx ~/engines/fukauraou/eval/model.onnx
```

配置後のフォルダ構成：

```
📁 ~/engines/fukauraou/
  📁 eval/
    📄 model.onnx      ← 推論モデルファイル
  FukauraOuLinux       ← 実行ファイル
```

必要なら `eval_options.txt` を `eval` 配下に置きます。dlshogiで使っていた `model.onnx.ini` 相当の設定は、この `eval_options.txt` に移し替える運用ができます。

### 2-4. 起動確認

```bash
cd ~/engines/fukauraou
./FukauraOuLinux
```

起動後、以下を順に入力して確認します。

```text
usi
isready
setoption name EvalDir value eval
bench
quit
```

`bench` が最後まで完走すれば、最低限の起動確認は完了です。

### 2-5. GPUなしでも起動可能な系統（ORT-CPU版）を入れる手順

GPUがないLinux環境では、TensorRT版ではなく ORT-CPU 版（ONNX Runtime CPU実行）をビルドして使います。

注意:

- GPU版に比べて大幅に遅くなります（解析用途・検証用途向け）
- モデルはONNX形式（`.onnx`）を使います

#### 2-5-1. ONNX Runtime を用意

```bash
cd ~
curl -LO https://github.com/microsoft/onnxruntime/releases/download/v1.11.1/onnxruntime-linux-x64-1.11.1.tgz
tar xzf onnxruntime-linux-x64-1.11.1.tgz
```

#### 2-5-2. ふかうら王をORT-CPU版でビルド

```bash
cd ~/YaneuraOu/source
make clean YANEURAOU_EDITION=YANEURAOU_ENGINE_DEEP_ORT_CPU
make -j$(nproc) normal \
  COMPILER=clang++ \
  YANEURAOU_EDITION=YANEURAOU_ENGINE_DEEP_ORT_CPU \
  TARGET_CPU=AVX2 \
  EXTRA_CPPFLAGS='-I/root/onnxruntime-linux-x64-1.11.1/include' \
  EXTRA_LDFLAGS='-L/root/onnxruntime-linux-x64-1.11.1/lib -fuse-ld=lld'
```

`/root/...` の部分は、実際に展開したパスに合わせて置き換えてください。たとえば通常ユーザーなら `~/onnxruntime-linux-x64-1.11.1/...` です。

例（一般的なホームディレクトリ配下）:

```bash
cd ~/YaneuraOu/source
make clean YANEURAOU_EDITION=YANEURAOU_ENGINE_DEEP_ORT_CPU
make -j$(nproc) normal \
  COMPILER=clang++ \
  YANEURAOU_EDITION=YANEURAOU_ENGINE_DEEP_ORT_CPU \
  TARGET_CPU=AVX2 \
  EXTRA_CPPFLAGS="-I$HOME/onnxruntime-linux-x64-1.11.1/include" \
  EXTRA_LDFLAGS="-L$HOME/onnxruntime-linux-x64-1.11.1/lib -fuse-ld=lld"
```

#### 2-5-3. 実行時ライブラリパスを設定

**推奨: ldconfig でシステム全体に登録する**

SSM セッションは非インタラクティブシェルで起動するため `~/.bashrc` が読み込まれません。
`~/.bashrc` への `export LD_LIBRARY_PATH=...` だけでは SSM 経由では効かず、以下のエラーが出ます。

```
error while loading shared libraries: libonnxruntime.so.1.11.1: cannot open shared object file: No such file or directory
```

`ldconfig` でシステムのライブラリ検索パスに登録するのが最も確実です。

```bash
# /etc/ld.so.conf.d/ に設定ファイルを追加
echo "$HOME/onnxruntime-linux-x64-1.11.1/lib" | sudo tee /etc/ld.so.conf.d/onnxruntime.conf
sudo ldconfig
```

登録確認:

```bash
ldconfig -p | grep onnxruntime
```

`libonnxruntime.so.1.11.1` が表示されれば完了です。再起動後も有効です。

補足: `~/.bashrc` への追記は通常のログインセッションでも有効にしたい場合のみ行います。

```bash
# ~/.bashrc への追記（SSM では効果なし、ローカルログイン時向け）
export LD_LIBRARY_PATH=$HOME/onnxruntime-linux-x64-1.11.1/lib:$LD_LIBRARY_PATH
```

#### 2-5-4. モデル配置と起動確認

```bash
mkdir -p ~/engines/fukauraou-cpu/eval
cp /path/to/model.onnx ~/engines/fukauraou-cpu/eval/
cp ./YaneuraOu-by-gcc ~/engines/fukauraou-cpu/FukauraOuCpu
cd ~/engines/fukauraou-cpu
./FukauraOuCpu
```

起動後:

```text
usi
isready
setoption name EvalDir value eval
bench
quit
```

`error while loading shared libraries: libonnxruntime.so...` が出る場合は、ライブラリパスの設定漏れが原因です。
特に SSM セッション（非インタラクティブシェル）では `~/.bashrc` が読まれないため、`LD_LIBRARY_PATH` の export だけでは解決しません。2-5-3 の ldconfig の手順を優先してください。

## 3. dlshogiのインストール

dlshogiは、USIエンジン利用とPythonライブラリ利用の2系統があります。GUIで対局させたいだけならUSIエンジンのビルドだけでも足ります。学習や前処理も行うならPythonパッケージも入れてください。

### 3-1. ソース取得

```bash
cd ~
git clone https://github.com/TadaoYamaoka/DeepLearningShogi.git
cd DeepLearningShogi
```

### 3-2. USIエンジンのビルド

`usi/Makefile` は CUDA と TensorRT を使う前提です。公式READMEではLinux向けに `g++` が案内されています。

```bash
cd ~/DeepLearningShogi/usi
make clean
make -j$(nproc) CC=g++
```

生成物は通常 `bin/usi` です。

```bash
ls -l ~/DeepLearningShogi/usi/bin/usi
```

運用用ディレクトリにコピーする例:

```bash
mkdir -p ~/engines/dlshogi
cp ~/DeepLearningShogi/usi/bin/usi ~/engines/dlshogi/dlshogi_usi
```

### 3-3. モデルファイルの配置

dlshogiは、実行ファイルと同じディレクトリにモデルを置く運用が基本です。

```bash
cp /path/to/model.onnx ~/engines/dlshogi/
```

定跡を使う場合は `book.bin` も同じ場所に置きます。

```bash
cp /path/to/book.bin ~/engines/dlshogi/
```

### 3-4. 起動確認

```bash
cd ~/engines/dlshogi
./dlshogi_usi
```

起動後、以下を入力して確認します。

```text
usi
isready
bench
quit
```

補足:

- 初回起動時は、モデルからTensorRTのシリアライズ済みエンジンを作るため時間がかかることがあります
- 実行ディレクトリに `.serialized` ファイルができれば正常な挙動です

### 3-5. Pythonパッケージとして導入する場合

学習やデータ変換も使う場合は、ルートでPythonパッケージも入れておくと扱いやすいです。

```bash
cd ~/DeepLearningShogi
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel numpy
pip install -e .
```

学習コードも使う場合は、PyTorchをCUDA対応版で別途入れます。PyTorchの対応CUDAバージョンは、手元で入れたCUDAと合わせてください。

例:

```bash
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
```

## 4. ふかうら王とdlshogiを同居させるときの注意

いちばん多い失敗は、TensorRTやcuDNNのバージョン衝突です。

対策:

- 同じCUDA系にそろえて両方をビルドする
- 片方ずつ別コンテナに分ける
- 実行時の `LD_LIBRARY_PATH` を起動スクリプト側で切り替える

簡単な起動スクリプト例:

```bash
#!/usr/bin/env bash
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/opt/tensorrt/lib:$LD_LIBRARY_PATH
exec /home/ubuntu/engines/dlshogi/dlshogi_usi "$@"
```

同様に、ふかうら王用も別スクリプトにしておくと混線しにくくなります。

## 5. よくあるエラー

### `error while loading shared libraries: libnvinfer.so...`

TensorRTの共有ライブラリが見えていません。

確認:

```bash
ldconfig -p | grep nvinfer
```

対処:

- TensorRTを正しく導入する
- `LD_LIBRARY_PATH` にTensorRTの `lib` を追加する
- `/etc/ld.so.conf.d/` に設定して `sudo ldconfig` を実行する

### `parseFromFile` で落ちる

ONNXモデルとTensorRTの互換性が崩れている可能性があります。

対処:

- 公式配布モデルを使う
- TensorRTのバージョンを見直す
- 古い `.serialized` を削除して再生成する

### `cudaSetDevice` やGPU初期化で失敗する

ドライバ、CUDA、Docker GPUパススルーのいずれかが不整合です。

確認:

```bash
nvidia-smi
```

### `nvcc: command not found`

CUDA Toolkitが未導入、またはPATH未設定です。

## 6. Dockerで分離する方法

直接ホストに依存ライブラリをそろえるのが面倒なら、Dockerを使う方法もあります。

参考:

- https://github.com/mizar/docker-jupyter-dlshogi/tree/main/engine_fukauraou_dlshogi

この系統のDockerfileでは、Ubuntu上にCUDA / cuDNN / TensorRT / clang / dlshogi / ふかうら王をまとめて構築しています。ライブラリ競合を避けたいなら、実機直ビルドよりDockerのほうが管理しやすいです。

## 7. 最低限の確認チェックリスト

- `nvidia-smi` が成功する
- `nvcc --version` が成功する
- ふかうら王が `usi` に応答する
- dlshogiが `usi` に応答する
- 両方とも `bench` が完走する
- モデル読込エラーが出ない

## 8. 参考コマンドまとめ

### ふかうら王

```bash
cd ~/YaneuraOu/source
make clean YANEURAOU_EDITION=YANEURAOU_ENGINE_DEEP_TENSOR_RT_UBUNTU
make -j$(nproc) tournament \
  COMPILER=clang++ \
  YANEURAOU_EDITION=YANEURAOU_ENGINE_DEEP_TENSOR_RT_UBUNTU \
  ENGINE_NAME="FukauraOuLinux" \
  TARGET_CPU=AVX2
```

### dlshogi

```bash
cd ~/DeepLearningShogi/usi
make clean
make -j$(nproc) CC=g++
```

### Python利用

```bash
cd ~/DeepLearningShogi
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel numpy
pip install -e .
```