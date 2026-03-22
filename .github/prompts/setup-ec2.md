# やること

## 1.dlshogiのwikiを確認する

[wiki](https://github.com/TadaoYamaoka/DeepLearningShogi/wiki)

インストールに必要なソフトウェアや環境を確認すること

## 2.環境構築からDLshougiのインストール

以下のコマンドでEC2に接続する

```
aws ssm start-session --target i-0d25fe44c6a0013aa --region us-east-1
```

1で整理した内容をもとにパッケージのインストールなどを行う。tensorはリポジトリのルート直下においてあるのでそれを利用すること。

## 3. UserDataにスクリプトを記載する

実行したコマンドを整理してdlshogi-userdata.shを修正してください。