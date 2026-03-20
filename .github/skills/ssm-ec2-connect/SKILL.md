---
name: ssm-ec2-connect
description: 'AWS Systems Manager (SSM) 経由で EC2 に接続する手順。Use when: ec2へ接続したい, ssm start-session, bastion不要でログインしたい。'
argument-hint: 'target には EC2 インスタンスID（例: i-0eb9d00f54bd4fdd1）を指定'
user-invocable: true
---

# SSM経由でEC2に接続

## このスキルでできること
- `aws ssm start-session --target <instance-id>` を使って EC2 に接続する。
- 接続前に必要な前提（認証・リージョン・SSM管理対象）を簡易チェックする。

## 使うタイミング
- EC2 へ SSH ではなく SSM で接続したいとき
- 踏み台サーバーなしでセッション接続したいとき
- 接続コマンドを毎回思い出す手間を減らしたいとき

## 手順
1. `target` に接続先インスタンスIDを用意する（例: `i-0eb9d00f54bd4fdd1`）。
2. AWS CLI の認証状態を確認する: `aws sts get-caller-identity`
3. 必要ならリージョンを確認/指定する（例: `--region ap-northeast-1`）。
4. 次のコマンドを実行する。
   - 基本: `aws ssm start-session --target <instance-id>`
   - 例: `aws ssm start-session --target i-0eb9d00f54bd4fdd1`
5. 接続後、必要な作業を実施する。

## 分岐（うまくいかない場合）
- `TargetNotConnected` が出る場合:
  - インスタンスが SSM 管理対象か確認する（SSM Agent, IAMロール, ネットワーク到達性）。
- `AccessDeniedException` が出る場合:
  - 実行ユーザー/ロールに `ssm:StartSession` など必要権限があるか確認する。
- リージョン違いの可能性がある場合:
  - `--region` を明示して再実行する。

## 完了チェック
- セッション開始メッセージが表示される。
- 接続先シェルでコマンドが実行できる。
