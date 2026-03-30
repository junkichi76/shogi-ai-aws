# shogi-ai-aws

AWS CDK（TypeScript）で Shogi AI エンジン（ふかうら王・dlshogi）を GPU EC2 インスタンス上にデプロイするプロジェクト。

Windows の ShogiGUI から SSH / SSM 経由でリモート接続して対局・解析に使う。

## アーキテクチャ

```
VPC (172.16.0.0/16)
└── Public Subnet /24
    ├── fukauraou  (g4dn.xlarge Spot, Ubuntu 20.04, 8GB)
    └── dlshogi    (g4dn.xlarge Spot, Ubuntu 22.04 Deep Learning AMI, 100GB)
```

## クイックスタート

```bash
# 依存パッケージのインストール
npm install

# 両方のエンジンをデプロイ（デフォルト）
npx cdk deploy

# ふかうら王のみ
npx cdk deploy -c engine=fukauraou

# dlshogi のみ
npx cdk deploy -c engine=dlshogi

# デプロイ内容の確認
npx cdk diff
npx cdk synth
```

## EC2 への接続

```bash
# SSM Session Manager（パブリック IP 不要）
aws ssm start-session --target <INSTANCE_ID> --region us-east-1
```

ShogiGUI からの接続方法は `docs/windows11-shogigui-usage.md` を参照。

## エンジンのセットアップ

デプロイ後、各インスタンス上でエンジンをビルドする必要がある。

- **dlshogi**: `scripts/dlshogi-userdata.sh` が初回起動時に TensorRT インストール・ビルド・モデルダウンロードまで自動実行する。
  Spot 中断後の再デプロイ時も同様に自動セットアップされる。手動で再ビルドが必要な場合は `scripts/dlshogi-build.sh` を使用。
- **ふかうら王**: `docs/linux-install-fukauraou-dlshogi.md` の手順に従って手動セットアップ。

TensorRT のインストール手順は `docs/dlshogi-ami-tensorrt.md` を参照。

## ドキュメント

| ファイル | 内容 |
|---------|------|
| `.github/PLAN.md` | プロジェクトの目的・やりたいこと |
| `.github/SPEC.md` | インフラ仕様・デプロイコマンド |
| `.github/TODO.md` | タスク管理（コンテキストリセット後の再開用） |
| `.github/KNOWLEDGE.md` | ハマりポイントと解決策のメモ |
| `docs/dlshogi-ami-tensorrt.md` | TensorRT のインストール手順 |
| `docs/linux-install-fukauraou-dlshogi.md` | エンジンのビルド・インストール手順 |
| `docs/linux-verify-software-install.md` | ソフトウェア動作確認チェックリスト |
| `docs/windows11-shogigui-usage.md` | ShogiGUI からの接続設定 |

## 開発コマンド

```bash
npm run build   # TypeScript コンパイル
npm run watch   # ウォッチモード
npm run test    # Jest テスト
```
