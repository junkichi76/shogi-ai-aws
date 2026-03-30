# dlshogi用AMIへのTensorRTインストール手順

## 前提環境

本プロジェクトのdlshogiデプロイで使用しているAMIは以下の通りです。

| 項目 | 値 |
|------|-----|
| AMI名 | Deep Learning OSS Nvidia Driver AMI GPU PyTorch 2.7 (Ubuntu 22.04) |
| SSMパラメータ | `/aws/service/deeplearning/ami/x86_64/oss-nvidia-driver-gpu-pytorch-2.7-ubuntu-22.04/latest/ami-id` |
| OS | Ubuntu 22.04 LTS |
| CUDAスタック | `/usr/local/cuda-12.8`（CUDA 12.8） |
| NVIDIAドライバ | 580.x系（OSS版） |
| GPUインスタンス | g4dn.xlarge（NVIDIA T4） |

最新のAMIリリースノートはNVIDIA DLAMIのドキュメントを参照してください。  
https://docs.aws.amazon.com/dlami/latest/devguide/aws-deep-learning-x86-gpu-pytorch-2.7-ubuntu-22-04.html

## インストール可能なTensorRTバージョン

CUDA 12.8に対応するTensorRTは **TensorRT 10.x系（CUDA 12.x対応ビルド）** です。

| TensorRT系列 | CUDA対応 | Ubuntu 22.04サポート | 備考 |
|-------------|---------|-------------------|------|
| TensorRT 10.x | CUDA 12.x（12.0〜12.9） | ○ | **現AMI向け推奨** |
| TensorRT 8.6.x | CUDA 12.0〜12.1のみ | △ | CUDA 12.8では動作しない |
| TensorRT 7.x | CUDA 11.x のみ | ✕ | Ubuntu 18.04向け（旧AMI用） |

> **注意**: 旧AMI（Ubuntu 18.04 / CUDA 11.0）で使用していた `TensorRT-7.1.3.4` は、現在のAMI（CUDA 12.8）では使用できません。TensorRT 10.x が必要です。

### dlshogi公式推奨との差異について

dlshogiの公式READMEでは CUDA 12.1 / TensorRT 8.6 が案内されていますが、本AMIは CUDA 12.8 を搭載しているため TensorRT 10.x を使用する必要があります。TensorRT 10.x は TensorRT 8.x と比較してAPIの変更が入っているため、dlshogiのソースコードがTensorRT 10.x に対応しているか事前に確認してください。

- dlshogi公式リポジトリ: https://github.com/TadaoYamaoka/DeepLearningShogi

## TensorRTのダウンロード手順

TensorRTのダウンロードには **NVIDIAデベロッパーアカウント**（無料）が必要です。

### ステップ1: NVIDIAデベロッパーポータルにアクセス

1. https://developer.nvidia.com/tensorrt にアクセスします
2. **GET STARTED** → **Download Now** をクリックします
3. NVIDIAアカウントでログインします（アカウントがなければ無料で作成できます）

### ステップ2: パッケージの選択

ダウンロードページで以下の条件に合致するパッケージを選択してください。

| 選択項目 | 値 |
|---------|-----|
| TensorRTバージョン | 10.x 系の最新安定版 |
| OS | Linux x86-64 |
| CUDA バージョン | 12.x |
| Ubuntu バージョン | 22.04 |

パッケージ形式は目的に応じて選択します。

| 形式 | ファイル例 | 用途 |
|------|-----------|------|
| Debian local repo（推奨） | `nv-tensorrt-local-repo-ubuntu2204-10.x.x-cuda-12.x_1.0-1_amd64.deb` | C++ヘッダ込みのシステムワイドインストール |
| tar.gz | `TensorRT-10.x.x.x.Ubuntu-22.04.x86_64-gnu.cuda-12.x.tar.gz` | 任意パスへの展開、複数バージョン共存 |
| pip（Python only） | PyPI経由 | Pythonのみ利用する場合（C++ヘッダ不可） |

> **dlshogiのソースビルドにはC++ヘッダが必要です**。Debianパッケージまたはtar.gzを選択してください。

## インストール手順

### 方法A: Debianパッケージ（推奨）

```bash
# ダウンロードしたdebファイルをEC2に転送した後:
sudo dpkg -i nv-tensorrt-local-repo-ubuntu2204-10.x.x-cuda-12.x_1.0-1_amd64.deb

# キーリングのコピー
sudo cp /var/nv-tensorrt-local-repo-ubuntu2204-10.x.x-cuda-12.x/*-keyring.gpg \
  /usr/share/keyrings/

# パッケージリストの更新とインストール
sudo apt-get update
sudo apt-get install -y tensorrt
```

インストール確認:

```bash
dpkg -l | grep nvinfer
python3 -c "import tensorrt as trt; print(trt.__version__)"
```

### 方法B: tar.gz展開

```bash
# ダウンロードしたtar.gzをEC2に転送した後:
tar xf TensorRT-10.x.x.x.Ubuntu-22.04.x86_64-gnu.cuda-12.x.tar.gz -C /opt/

# ヘッダとライブラリをCUDAの標準パスに配置
TRTDIR=/opt/TensorRT-10.x.x.x
sudo cp ${TRTDIR}/include/* /usr/local/cuda/include/
sudo cp ${TRTDIR}/lib/*.so* /usr/local/cuda/lib64/
sudo ldconfig
```

ライブラリの確認:

```bash
ldconfig -p | grep nvinfer
```

### 方法C: pip（Pythonのみ）

dlshogiのソースビルドには使用できませんが、Python推論用途では最も簡単です。

```bash
# CUDA 12.x向けパッケージ
pip install --upgrade tensorrt-cu12
```

確認:

```bash
python3 -c "import tensorrt as trt; print(trt.__version__)"
```

## EC2へのファイル転送

ダウンロードしたパッケージはローカルPCからEC2インスタンスに転送する必要があります。

### SCPを使った転送例

```bash
# SSMセッションマネージャー経由でのポートフォワーディングを使う場合
scp -i ~/.ssh/your-key.pem \
  TensorRT-10.x.x.x.Ubuntu-22.04.x86_64-gnu.cuda-12.x.tar.gz \
  ubuntu@<EC2_PUBLIC_IP>:/tmp/
```

### S3経由での転送（推奨）

スクリプト自動化やIAMロール活用のために、S3バケット経由が推奨です。

```bash
# ローカルからS3にアップロード
aws s3 cp TensorRT-10.x.x.x.Ubuntu-22.04.x86_64-gnu.cuda-12.x.tar.gz \
  s3://<YOUR_BUCKET>/tensorrt/

# EC2上でS3からダウンロード（IAMロールによるアクセス）
aws s3 cp s3://<YOUR_BUCKET>/tensorrt/TensorRT-10.x.x.x.Ubuntu-22.04.x86_64-gnu.cuda-12.x.tar.gz \
  /tmp/TensorRT.tar.gz
```

## 参考情報

- TensorRT公式インストールガイド: https://docs.nvidia.com/deeplearning/tensorrt/latest/installing-tensorrt/installing.html
- TensorRTサポートマトリクス: https://docs.nvidia.com/deeplearning/tensorrt/latest/getting-started/support-matrix.html
- AWS DLAMI リリースノート（PyTorch 2.7 Ubuntu 22.04）: https://docs.aws.amazon.com/dlami/latest/devguide/aws-deep-learning-x86-gpu-pytorch-2.7-ubuntu-22-04.html
- dlshogiリポジトリ: https://github.com/TadaoYamaoka/DeepLearningShogi
