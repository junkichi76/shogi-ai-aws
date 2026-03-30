# PLAN.md

## 目的

AWS 上で Shogi AI エンジン（ふかうら王・dlshogi）を GPU インスタンスで動かし、
Windows ShogiGUI からリモート接続して対局・解析を行えるようにする。

## 背景・やりたいこと

- クラウド GPU を必要なときだけ使ってコストを抑えたい（Spot Instance 活用）
- IaC（AWS CDK）で環境を再現可能にする → 使い捨て運用が可能
- Windows の ShogiGUI から SSH / SSM 経由でエンジンに接続する

## 現状のアーキテクチャ

```
VPC (172.16.0.0/16)
└── Public Subnet /24
    ├── fukauraou EC2 (g4dn.xlarge Spot, Ubuntu 20.04, 8GB)
    └── dlshogi   EC2 (g4dn.xlarge Spot, Ubuntu 22.04 Deep Learning AMI, 100GB)
```

- デプロイは `cdk deploy -c engine=fukauraou|dlshogi|both|none` で切り替え可能
- 接続は SSM Session Manager（パブリック IP 不要）または SSH

## やりたいこと（中期）

dlshogi側を安定稼働させる

1. **自動ビルドの完成**
   - TensorRTについて結論を出す
     - 互換パッチを当てているがこれは本当に必要か、また必要な場合公式で推奨されているか
     - s3経由でインストールをする必要が本当にあるか
   - Spot 中断後も再起動で即使える状態にする
   - shougiguiでエンジンとして指定するスクリプト

2. **ShogiGUI 接続スクリプトの整備**
   - 現状の `ssm-ssh-ec2.cmd` はインスタンス ID がハードコードされている問題を解決

3. **環境構築についてReadMeに記載する**
   - バッチを実行するだけで環境が作成されるのが理想


## 方針

- dlshogi と ふかうら王 の共存はライブラリ衝突リスクがあるため、**別インスタンスで分離**（現状維持）
- Spot 中断でデータが消えることを前提に、**S3 をストレージ基盤にした使い捨て設計**を推進する
- ふかうら王は後回しdlshoginの完成を優先
