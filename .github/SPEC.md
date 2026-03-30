# SPEC.md

Claude との仕様認識を合わせるためのドキュメント。

## インフラ仕様

### VPC

| 項目 | 値 |
|------|-----|
| CIDR | 172.16.0.0/16 |
| AZ 数 | 1 |
| サブネット | Public Subnet /24（パブリック IP 自動割り当て） |

### EC2（共通）

| 項目 | 値 |
|------|-----|
| インスタンスタイプ | g4dn.xlarge |
| GPU | NVIDIA T4 |
| 起動方式 | Spot Instance（中断時: TERMINATE） |
| SSH キー | shogi-ai-keypair（既存のキーペアを参照） |
| IAM ロール | AmazonSSMManagedInstanceCore |

### ふかうら王インスタンス

| 項目 | 値 |
|------|-----|
| AMI | Ubuntu 20.04 LTS（Ubuntu Server 公式） |
| SSM パラメータ | `/aws/service/canonical/ubuntu/server/20.04/stable/current/amd64/hvm/ebs-gp2/ami-id` |
| ルートボリューム | 8 GB |
| userdata | なし（将来: fukauraou-userdata.sh） |

### dlshogi インスタンス

| 項目 | 値 |
|------|-----|
| AMI | Deep Learning OSS NVIDIA Driver GPU PyTorch 2.7 (Ubuntu 22.04) |
| SSM パラメータ | `/aws/service/deeplearning/ami/x86_64/oss-nvidia-driver-gpu-pytorch-2.7-ubuntu-22.04/latest/ami-id` |
| CUDA | 12.8（`/usr/local/cuda-12.8`） |
| NVIDIA ドライバ | 580.x 系（OSS 版） |
| ルートボリューム | 100 GB |
| userdata | `scripts/dlshogi-userdata.sh` |

## デプロイコマンド

```bash
# 依存パッケージインストール
npm install

# TypeScript ビルド
npm run build

# テスト
npm run test

# CloudFormation テンプレート生成（確認用）
npx cdk synth

# デプロイ（両方がデフォルト）
npx cdk deploy

# ふかうら王のみ
npx cdk deploy -c engine=fukauraou

# dlshogi のみ
npx cdk deploy -c engine=dlshogi

# 差分確認
npx cdk diff
```

## EC2 接続方法

### SSM Session Manager（パブリック IP 不要・推奨）

```bash
aws ssm start-session --target <INSTANCE_ID> --region us-east-1
```

### SSH（パブリック IP 経由）

```bash
ssh -i shogi-ai-keypair.pem ubuntu@<PUBLIC_IP>
```

### SSH + SSM トンネル（パブリック IP 不要、SSH が必要な場合）

```bash
ssh -i "C:\path\to\shogi-ai-keypair.pem" \
  -o ProxyCommand="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=22" \
  ubuntu@<INSTANCE_ID>
```

## ソフトウェア仕様

### ふかうら王

| 項目 | 値 |
|------|-----|
| ソースリポジトリ | https://github.com/yaneurao/YaneuraOu |
| ビルドエディション | `YANEURAOU_ENGINE_DEEP_TENSOR_RT_UBUNTU` |
| コンパイラ | clang++ |
| モデル形式 | ONNX |
| モデル配置先 | `~/engines/fukauraou/eval/model.onnx` |
| 実行ファイル配置先 | `~/engines/fukauraou/FukauraOuLinux` |

### dlshogi

| 項目 | 値 |
|------|-----|
| ソースリポジトリ | https://github.com/TadaoYamaoka/DeepLearningShogi |
| ビルドコマンド | `make -j$(nproc) CC=g++` |
| モデル形式 | ONNX |
| モデル配置先 | `~/engines/dlshogi/model.onnx` |
| 実行ファイル配置先 | `~/engines/dlshogi/dlshogi_usi` |

### TensorRT（dlshogi・ふかうら王共通）

| 項目 | 値 |
|------|-----|
| 必要バージョン | TensorRT 10.x（CUDA 12.x 対応ビルド） |
| 取得元 | https://developer.nvidia.com/tensorrt（要 NVIDIA 開発者アカウント） |
| 推奨インストール方式 | Debian パッケージ |

> **重要**: dlshogi 公式 README は CUDA 12.1 + TensorRT 8.6 を案内しているが、
> 本 AMI は CUDA 12.8 のため **TensorRT 10.x が必要**。

## ShogiGUI 接続設定

ShogiGUI でエンジン登録する際のコマンド例（SSM 経由 SSH）:

```bat
"C:\Program Files\Git\bin\ssh.exe" -i "C:\path\to\shogi-ai-keypair.pem" ^
  -o "ProxyCommand=C:\path\to\aws ssm start-session --target %%h --document-name AWS-StartSSHSession --parameters portNumber=22" ^
  ubuntu@<INSTANCE_ID> "cd ~/engines/dlshogi && ./dlshogi_usi"
```

詳細は `docs/windows11-shogigui-usage.md` を参照。
