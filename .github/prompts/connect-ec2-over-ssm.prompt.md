---
name: connect-ec2-over-ssm
description: 'このリポジトリの EC2 へ SSH over SSM で接続する。CDK output から instance ID を取得し、PowerShell の接続コマンドを組み立て、必要なら接続確認や切り分けまで行う。'
argument-hint: 'engine=dlshogi|fukauraou, user=ubuntu|ec2-user, keyPath=C:\\Users\\akiya\\shogi-ai-keypair.pem'
agent: agent
---
Related skill: `ec2-ssh-over-ssm`.

このリポジトリの CDK スタックが作成した EC2 に、SSH over SSM で接続してください。

入力から以下を解釈してください。

- `engine`: `dlshogi` または `fukauraou`
- `user`: SSH ログインユーザー。未指定なら Ubuntu 系を優先して `ubuntu`
- `keyPath`: Windows 上の秘密鍵パス。未指定なら `C:\Users\akiya\shogi-ai-keypair.pem`
- `mode`: 未指定なら PowerShell 対話接続。必要なら `check` または `shogigui`

実行方針:

1. まず [ec2-ssh-over-ssm skill](../skills/ec2-ssh-over-ssm/SKILL.md) の手順に従う。
2. `engine` に応じて CloudFormation output key を選ぶ。
   - `dlshogi` → `DlshogiInstanceId`
   - `fukauraou` → `FukauraOUInstanceId`
3. `ShogiAiAwsStack` の output から instance ID を取得する。
4. AWS 認証が怪しい場合は `aws sts get-caller-identity` で確認し、必要なら `aws-sso-login` スキルの流れを使う。
5. PowerShell 用の `ssh` コマンドを組み立てる。`ProxyCommand` には `aws ssm start-session --document-name AWS-StartSSHSession` を使い、リージョンは `us-east-1` とする。
6. `mode=check` の場合は `echo ok` で疎通確認コマンドを優先する。
7. `mode=shogigui` の場合は `.cmd` ラッパーの内容を生成する。
8. 失敗した場合は、CloudFormation output、SSM、SSH、鍵、ユーザー名の順で切り分ける。

出力要件:

- 最初に、何を取得し何を実行するかを短く述べる。
- 次に、使う PowerShell コマンドをそのまま実行できる形で示す。
- 実際にコマンドを実行した場合は、成功可否と次の一手を簡潔に述べる。
- `mode=shogigui` の場合は `.cmd` の完全な内容を示す。

不足情報がある場合だけ、次の優先順で最小限確認する。

1. `engine`
2. `keyPath`（未指定時は `C:\Users\akiya\shogi-ai-keypair.pem` を使う）
3. `user`

情報が十分なら質問せず、そのまま進める。