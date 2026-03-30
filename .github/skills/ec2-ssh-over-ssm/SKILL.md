---
name: ec2-ssh-over-ssm
description: 'このリポジトリの EC2 へ SSM を使って SSH 接続するワークフロー。CDK output からインスタンス ID を取得し、公開 IP なしで接続確認し、ssh ProxyCommand を組み立てる。Use when: ec2 に ssh over ssm で接続, ssm 経由 ssh, AWS-StartSSHSession, ProxyCommand, cdk output から instance id 取得, 公開IPなしでEC2接続'
argument-hint: '対象エンジン名、OS ユーザー名、秘密鍵パス。未確定なら既知情報だけでよい'
---

# EC2 へ SSH over SSM で接続

## 目的

このワークスペースの CDK スタックが作成した EC2 に対して、Windows 環境から公開 IP を使わずに AWS Systems Manager Session Manager を経由して SSH 接続する。

主対象は PowerShell からの対話 SSH 接続とする。ShogiGUI 連携は必要時のみ補助的に扱う。

---

## 使う場面

- EC2 に公開 IP を付けたくない
- `aws ssm start-session` は通るが、SSH で安定接続したい
- `ProxyCommand=aws ssm start-session ... AWS-StartSSHSession` を組み立てたい
- CDK output から対象のインスタンス ID を取りたい
- 接続エラー時に、認証、SSM、SSH のどこが詰まっているか切り分けたい

---

## 前提条件

以下を順番に満たしていることを確認する。

1. AWS CLI が使える

```powershell
aws --version
```

2. Session Manager Plugin が使える

```powershell
session-manager-plugin
```

3. AWS 認証が有効

- SSO を使う場合は `aws-sso-login` スキルの手順を実行する
- その後、以下で認証状態を確認する

```powershell
aws sts get-caller-identity
```

4. 対象 EC2 が SSM 管理下にある

```powershell
aws ssm describe-instance-information --query "InstanceInformationList[].InstanceId"
```

5. 対象 EC2 で SSH サーバーが動いている

- Ubuntu 系なら通常は `ubuntu` ユーザー
- Amazon Linux 系なら通常は `ec2-user` ユーザー
- `ssm-user` は SSH 用ではなく、既定ユーザーにしない

6. 秘密鍵が手元にある

- 既定値: `C:\Users\akiya\shogi-ai-keypair.pem`

---

## 基本フロー

### 1. CDK output から対象インスタンス ID を取得する

このリポジトリのスタック名は通常 `ShogiAiAwsStack`。

- dlshogi は `DlshogiInstanceId`
- ふかうら王は `FukauraOUInstanceId`

```powershell
# dlshogi
$INSTANCE_ID = aws cloudformation describe-stacks `
  --stack-name ShogiAiAwsStack `
  --query "Stacks[0].Outputs[?OutputKey=='DlshogiInstanceId'].OutputValue" `
  --output text `
  --region us-east-1

# ふかうら王
$INSTANCE_ID = aws cloudformation describe-stacks `
  --stack-name ShogiAiAwsStack `
  --query "Stacks[0].Outputs[?OutputKey=='FukauraOUInstanceId'].OutputValue" `
  --output text `
  --region us-east-1
```

値が `None` や空文字になる場合は、対象エンジンが未デプロイか、output 名を取り違えている。

### 2. まず SSM セッション単体が通るか確認する

```powershell
aws ssm start-session --target $INSTANCE_ID --region us-east-1
```

これが通らない場合、SSH 以前に IAM ロール、SSM Agent、認証の問題である。

### 3. PowerShell で SSH over SSM を確認する

```powershell
ssh -i "C:\Users\akiya\shogi-ai-keypair.pem" `
  -o StrictHostKeyChecking=no `
  -o UserKnownHostsFile=NUL `
  -o ServerAliveInterval=30 `
  -o ServerAliveCountMax=3 `
  -o "ProxyCommand=aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartSSHSession --parameters portNumber=22 --region us-east-1" `
  <USER>@$INSTANCE_ID "echo ok"
```

`ok` が返れば、SSM トンネル経由の SSH は成立している。

### 4. 対話シェルで接続する

```powershell
ssh -i "C:\Users\akiya\shogi-ai-keypair.pem" `
  -o StrictHostKeyChecking=no `
  -o UserKnownHostsFile=NUL `
  -o ServerAliveInterval=30 `
  -o ServerAliveCountMax=3 `
  -o "ProxyCommand=aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartSSHSession --parameters portNumber=22 --region us-east-1" `
  <USER>@$INSTANCE_ID
```

### 5. 必要なら ShogiGUI 用の .cmd ラッパーを作る

```bat
@echo off
set KEY=C:\Users\akiya\shogi-ai-keypair.pem
set INSTANCE_ID=i-xxxxxxxxxxxxxxxxx
set USER=ubuntu

ssh -i %KEY% ^
  -o StrictHostKeyChecking=no ^
  -o UserKnownHostsFile=NUL ^
  -o ServerAliveInterval=30 ^
  -o ServerAliveCountMax=3 ^
  -o "ProxyCommand=aws ssm start-session --target %INSTANCE_ID% --document-name AWS-StartSSHSession --parameters portNumber=22 --region us-east-1" ^
  %USER%@%INSTANCE_ID% "cd ~/engines/dlshogi && ./dlshogi_usi"
```

ShogiGUI 連携では、`aws ssm start-session` を直接たたく方式よりも、この SSH over SSM 方式を優先する。

---

## 判断分岐

### CDK output からインスタンス ID が取れない場合

以下を確認する。

- `cdk deploy` が成功しているか
- 対象エンジンを `-c engine=dlshogi` などでデプロイしたか
- stack 名が `ShogiAiAwsStack` で合っているか
- output key 名が `DlshogiInstanceId` または `FukauraOUInstanceId` で合っているか

### `aws ssm start-session` が失敗する場合

以下を確認する。

- AWS 認証が切れていないか
- EC2 IAM ロールに `AmazonSSMManagedInstanceCore` があるか
- SSM Agent が起動しているか
- 対象リージョンが正しいか

### SSM は通るが SSH が失敗する場合

以下を確認する。

- ユーザー名が正しいか (`ubuntu` / `ec2-user`)
- 対応する秘密鍵を使っているか
- EC2 内で `sshd` が起動しているか
- `authorized_keys` が正しく配置されているか

### ShogiGUI では失敗するが PowerShell では成功する場合

以下を確認する。

- `.cmd` の改行継続 `^` が壊れていないか
- 起動コマンドが標準出力を汚していないか
- `cd ~/engines/... && ./binary` の作業ディレクトリが正しいか
- エンジン単体で `usi` `isready` `quit` が通るか

---

## 完了条件

以下をすべて満たせば完了。

1. `aws sts get-caller-identity` が成功する
2. `aws ssm start-session --target <INSTANCE_ID>` が成功する
3. `ssh ... "echo ok"` が `ok` を返す
4. 対話 SSH が成功する
5. 必要なら ShogiGUI 用 `.cmd` からエンジン起動まで通る

---

## よくある失敗

- `ssm-user` を SSH ログインユーザーにしてしまう
- CDK output ではなく古い固定 instance ID を使い続ける
- Session Manager Plugin 未導入
- SSO ログイン切れ
- `--region` の付け忘れ
- `AWS-StartSSHSession` ではなく別ドキュメントを使ってしまう
- Windows のパスを引用符なしで渡して秘密鍵パス解決に失敗する

---

## すぐ使える依頼例

- `CDK output から dlshogi の instance id を取って ssh over ssm で接続して。ユーザーは ubuntu、鍵は C:\\Keys\\shogi.pem` 
- `CDK output を使って ふかうら王の EC2 に PowerShell から入るコマンドを組んで` 
- `ShogiGUI から dlshogi を SSM 経由で起動する .cmd を作って` 
- `aws ssm は通るが ssh over ssm が失敗する。切り分けして` 
- `公開IPなしで EC2 に接続したい。PowerShell 用コマンドを組んで`