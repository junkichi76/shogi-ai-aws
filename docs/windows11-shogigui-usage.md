# Windows 11 の ShogiGUI から ふかうら王（AWS EC2上）を使う手順

この手順は、以下の前提で書いています。

- ふかうら王は AWS EC2（Linux）上で動作済み
- GUI は Windows 11 側の ShogiGUI を使う

---

## 1. 全体像

ShogiGUI は「標準入出力（stdin/stdout）で USI 通信できる実行ファイル」をエンジンとして扱います。  
EC2 上のふかうら王を使うには、Windows 側に `*.cmd` ラッパーを作り、内部で `ssh`（または `aws ssm`）を使って EC2 上のふかうら王を起動します。

---

## 2. 事前確認（EC2側）

EC2 にログインして、ふかうら王が単体で起動することを確認します。

```bash
cd ~/engines/fukauraou
./FukauraOuLinux
```

起動後に次を入力して応答を確認:

```text
usi
isready
quit
```

---

## 3. 方式A（推奨）: SSH で ShogiGUI から接続

公開IPまたは踏み台経由で SSH できる場合はこの方式が簡単です。

### 3-1. Windows 側で接続確認

PowerShell で確認:

```powershell
ssh -i C:\Keys\my-ec2-key.pem ubuntu@<EC2_HOSTNAME_OR_IP> "echo ok"
```

`ok` が返れば準備完了です。

### 3-2. ShogiGUI用ラッパー作成

例: `C:\ShogiEngines\ec2-fukauraou\engine_fukauraou_ec2.cmd`

```bat
@echo off
set KEY=C:\Keys\my-ec2-key.pem
set HOST=ubuntu@<EC2_HOSTNAME_OR_IP>
ssh -i %KEY% -o ServerAliveInterval=30 -o ServerAliveCountMax=3 %HOST% "cd ~/engines/fukauraou && ./FukauraOuLinux"
```

> EC2 のデフォルトユーザー名は AMI により異なります（`ubuntu` / `ec2-user` など）。

---

## 4. 方式B: SSM を使う（公開IPなし）

EC2 を Systems Manager 管理下に置いている場合はこちらを使えます。

前提:

- Windows に AWS CLI + Session Manager Plugin 導入済み
- EC2 に SSM Agent と適切な IAM ロールが設定済み

### 4-1. 直接 `start-session` 方式（非推奨）

例: `engine_fukauraou_ec2_ssm.cmd`

```bat
@echo off
set INSTANCE_ID=i-xxxxxxxxxxxxxxxxx
aws ssm start-session --target %INSTANCE_ID% --document-name AWS-StartInteractiveCommand --parameters command="cd ~/engines/fukauraou && ./FukauraOuLinux"
```

この方式は以下の理由で ShogiGUI 連携に失敗しやすいです。

- `Starting session with SessionId ...` などのメッセージが混ざり、USI 通信を汚染することがある
- PTY（対話端末）前提のため、エンジン標準入出力との相性が悪い場合がある

### 4-2. SSMトンネル + SSH 方式（推奨）

公開IPなしでも、SSM を ProxyCommand として使い、ShogiGUI 側は SSH エンジンとして扱うほうが安定します。

例: `engine_fukauraou_ec2_ssm_ssh.cmd`

```bat
@echo off
set KEY=C:\Keys\my-ec2-key.pem
set INSTANCE_ID=i-xxxxxxxxxxxxxxxxx
set USER=ubuntu

ssh -i %KEY% -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o "ProxyCommand=aws ssm start-session --target %INSTANCE_ID% --document-name AWS-StartSSHSession --parameters portNumber=22" %USER%@%INSTANCE_ID% "cd ~/engines/fukauraou && ./FukauraOuLinux"
```

> 方式Bを使う場合は、まずこの 4-2 を試してください。

---

## 5. ShogiGUI への登録

1. ShogiGUI を起動
2. エンジン設定を開く
3. 「追加」で作成した `engine_fukauraou_ec2.cmd`（または SSM 版）を選択
4. エンジン名を設定（例: `FukauraOu-EC2`）
5. 読み込み後、`isready` が通ることを確認

---

## 6. よくあるトラブル

### 6-1. ShogiGUIで初期化失敗

- `cmd` を単体起動してエラーを確認
- 同じ接続コマンドを PowerShell で直接実行して再現確認
- `aws ssm start-session` の開始/終了メッセージが混ざっていないか確認
- SSM 直接方式を使っている場合は 4-2（SSMトンネル + SSH）へ切り替える

### 6-2. SSH接続できない

- セキュリティグループで 22/tcp が許可されているか
- キーファイル・ユーザー名・ホスト名が正しいか
- `known_hosts` の不整合がないか

### 6-3. EC2上では動くが ShogiGUI から不安定

- `ssh` オプションに `ServerAliveInterval` を入れる
- セッション切断が多い場合は近いリージョンのEC2を使う

### 6-4. GPUを使っていないように見える

- EC2 で `nvidia-smi` を確認
- ふかうら王実行ユーザーから CUDA / ライブラリが参照できるか確認

---

## 7. 最小チェックリスト

- EC2 上のふかうら王単体起動で `usi` / `isready` が成功
- Windows から `ssh ... "cd ... && ./FukauraOuLinux"` が成功
- `engine_fukauraou_ec2.cmd` 単体起動で応答する
- ShogiGUI でエンジン登録できる
- `isready` が成功する
