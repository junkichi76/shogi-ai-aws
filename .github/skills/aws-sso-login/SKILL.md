---
name: aws-sso-login
description: 'AWS SSO 認証を実行するワークフロー。aws sso login、プロファイル確認、CDK デプロイ前の認証切れ対応、クレデンシャル検証に使用する。Use when: aws sso login, sso 認証, 認証切れ, ExpiredToken, UnauthorizedAccess, cdk deploy 前の認証'
argument-hint: '対象の AWS プロファイル名（省略時はデフォルトプロファイル）'
---

# AWS SSO ログイン

## 目的

AWS SSO（IAM Identity Center）を使って認証し、CDK デプロイや AWS CLI 操作で使えるクレデンシャルを取得する。

---

## ステップ

### 1. プロファイルの確認

`~/.aws/config` に SSO 設定があるか確認する。

```powershell
Get-Content "$env:USERPROFILE\.aws\config"
```

SSO プロファイルの例:

```ini
[default]
sso_session = default
sso_account_id = 242201288320
sso_role_name = AWSAdministratorAccess
region = ap-northeast-1

[sso-session default]
sso_start_url = https://d-9567529366.awsapps.com/start/#
sso_region = ap-northeast-1
sso_registration_scopes = sso:account:access
```

設定がない場合は先に `aws configure sso` を実行してプロファイルを作成する。

---

### 2. SSO ログインの実行

```powershell
# デフォルトプロファイルを使う場合
aws sso login

# プロファイルを指定する場合
aws sso login --profile <プロファイル名>
```

- ブラウザが自動で開く
- AWS SSO のサインイン画面で認証する
- "Request approved" が表示されたら認証完了

---

### 3. 認証の確認

```powershell
# デフォルトプロファイルを使う場合
aws sts get-caller-identity

# プロファイルを指定する場合
aws sts get-caller-identity --profile <プロファイル名>
```

成功例:

```json
{
    "UserId": "AROATQZCSL2AEWSZ42YSO:AWSAdmin@...",
    "Account": "242201288320",
    "Arn": "arn:aws:sts::242201288320:assumed-role/AWSReservedSSO_AWSAdministratorAccess_.../AWSAdmin@..."
}
```

エラーが出る場合は手順 2 からやり直す。

---

### 4. CDK デプロイ（本プロジェクト）

認証確認後、CDK コマンドを実行する。

```powershell
# 差分確認
npx cdk diff

# デプロイ
npx cdk deploy
```

---

## よくあるエラーと対処

| エラー | 原因 | 対処 |
|--------|------|------|
| `Error loading SSO Token` | トークン期限切れ | `aws sso login` を再実行 |
| `ExpiredTokenException` | クレデンシャル有効期限切れ | 同上 |
| `Profile not found` | プロファイル名が違う | `Get-Content ~/.aws/config` でプロファイル名を確認 |
| ブラウザが開かない | ヘッドレス環境など | `aws sso login --no-browser` で URL を手動コピー |
| `UnauthorizedAccess` | ロールの権限不足 | IAM Identity Center でロール割り当てを確認 |

---

## SSO セッションの有効期限

- デフォルトは **8 時間**（組織設定による）
- 期限切れの場合は `aws sso login` を再実行するだけでよい
- `aws sso logout` で明示的にログアウトも可能
- デフォルトプロファイルは `~/.aws/config` の `[default]` セクションまたは `AWS_DEFAULT_PROFILE` 環境変数で決まる

---

## 関連コマンド

```powershell
# 全プロファイル一覧
aws configure list-profiles

# キャッシュされた SSO トークンの確認
Get-ChildItem "$env:USERPROFILE\.aws\sso\cache\"

# キャッシュの削除（問題発生時）
Remove-Item "$env:USERPROFILE\.aws\sso\cache\*"
aws sso login
```
