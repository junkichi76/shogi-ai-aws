# TODO.md

コンテキストをリセットしても再開できるようにタスクを管理する。

## 再開手順

1. `PLAN.md` でやりたいことを確認
2. `SPEC.md` でインフラ仕様を確認
3. `KNOWLEDGE.md` で過去の知見を確認
4. このファイルで残タスクを確認
5. `npx cdk diff` で現在のデプロイ状態を確認

---

## 🔴 未着手

### [INFRA-2] ふかうら王 userdata スクリプト作成

**概要**: FukauraOU インスタンスにも起動時自動セットアップを追加する。

**手順**:
1. `scripts/fukauraou-userdata.sh` を新規作成
   - 依存パッケージのインストール（clang, lld, libomp-dev, libopenblas-dev 等）
   - CUDA パス設定
   - YaneuraOu リポジトリのクローン
   - TensorRT インストール後にビルドするスクリプトを配置
2. `lib/shogi-ai-aws-stack.ts` で fukauraou インスタンスに userdata を追加

**関連ファイル**: `lib/shogi-ai-aws-stack.ts`, `docs/linux-install-fukauraou-dlshogi.md`

---

### [INFRA-3] ShogiGUI 接続スクリプトの整備

**概要**: エンジンごとに接続用 .cmd スクリプトを用意する。

**手順**:
1. `ssm-ssh-dlshogi.cmd` を作成（dlshogi 接続専用）
2. `ssm-ssh-fukauraou.cmd` を作成（ふかうら王接続専用）
3. インスタンス ID をハードコードせず、AWS CLI で自動取得するか引数で受け取る形式にする

**関連ファイル**: `ssm-ssh-ec2.cmd`, `docs/windows11-shogigui-usage.md`

---

### [INFRA-4] モデルファイル・バイナリの S3 管理

**概要**: Spot 中断後の再起動を高速化するため、ビルド済みバイナリとモデルファイルを S3 でキャッシュする。

**実装済み**:
- CDK スタックに `DlshogiArtifacts` S3 バケット（`removalPolicy: RETAIN`）を追加
- dlshogi IAM ロールに S3 read/write 権限を付与
- `scripts/dlshogi-userdata.sh` を S3 キャッシュ対応に更新

**S3 キャッシュのリセット（TRT バージョン更新時など）**:
```bash
BUCKET=$(aws cloudformation describe-stacks --stack-name ShogiAiAwsStack \
  --query "Stacks[0].Outputs[?OutputKey=='ArtifactsBucketName'].OutputValue" \
  --output text --region us-east-1)
aws s3 rm "s3://$BUCKET/dlshogi/" --recursive
```

**関連ファイル**: `lib/shogi-ai-aws-stack.ts`, `scripts/dlshogi-userdata.sh`

---

### [DEV-1] Jest テストの実装

**概要**: 現在テストがコメントアウトのまま。CDK スタックの基本的なアサーションを追加する。

**手順**:
1. `test/shogi-ai-aws.test.ts` に以下のテストを追加:
   - VPC が作成されること
   - fukauraou インスタンスの LaunchTemplate が g4dn.xlarge であること
   - dlshogi インスタンスの LaunchTemplate が g4dn.xlarge であること
   - 各インスタンスに SSM ポリシーがアタッチされていること

**関連ファイル**: `test/shogi-ai-aws.test.ts`

---

## ✅ 完了

- CDK スタック基本構成（VPC + fukauraou + dlshogi EC2）
- SSM アクセス設定（AmazonSSMManagedInstanceCore）
- Spot Instance 設定（g4dn.xlarge, 中断時 TERMINATE）
- dlshogi userdata スクリプト（TensorRT apt インストール + ビルド + モデル配置を自動化）
- dlshogi S3 アーティファクトキャッシュ（バイナリ・モデル）とバケット CDK 管理（INFRA-1, INFRA-4）
- ShogiGUI 接続スクリプト `ssm-ssh-ec2.cmd` の動的インスタンス ID 取得対応（INFRA-3）
- ShogiGUI 接続手順ドキュメント（docs/windows11-shogigui-usage.md）
- TensorRT インストール手順ドキュメント（docs/dlshogi-ami-tensorrt.md）
- ふかうら王・dlshogi インストール手順ドキュメント（docs/linux-install-fukauraou-dlshogi.md）
- リポジトリドキュメント整備（PLAN.md / SPEC.md / TODO.md / KNOWLEDGE.md）
