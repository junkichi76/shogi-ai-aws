# KNOWLEDGE.md

一度ハマったことには二度とハマらないための知見メモ。

---

## AWS / インフラ系

### CUDA バージョンと TensorRT の対応

**現象**: dlshogi 公式 README の手順通りに進めても TensorRT が動かない。

**原因**:
- 公式 README は CUDA 12.1 + TensorRT 8.6 を案内している
- 本プロジェクトで使用している AMI（Deep Learning OSS NVIDIA Driver GPU PyTorch 2.7 Ubuntu 22.04）には **CUDA 12.8** が入っている
- TensorRT 8.6 は CUDA 12.2 以降では動作しない

**正しい対応**:
- CUDA 12.8 に対応する **TensorRT 10.x** を使う
- TensorRT 10.x は 8.x と比較して API 変更があるため、dlshogi が対応しているか要確認

| TensorRT 系列 | 対応 CUDA | 備考 |
|---|---|---|
| TensorRT 10.x | CUDA 12.x（12.0〜12.9） | **本 AMI 向け** |
| TensorRT 8.6.x | CUDA 12.0〜12.1 のみ | 本 AMI では動作しない |

---

### TensorRT 10.x 互換パッチについて

**結論**: パッチは必要、S3 経由インストールは不要。

- Deep Learning AMI の NVIDIA apt リポジトリから `apt-get install -y tensorrt` で TRT 10.x が入る（S3 経由は不要）
- dlshogi のソースコードは TRT 8.x の API（`setMaxBatchSize`, `setMaxWorkspaceSize`, `getBindingDimensions`, `enqueue`, `-lnvparsers`）を使用しており、これらは TRT 10 で削除・変更された
- TRT 10 対応のための互換パッチが必要（公式ではなくプロジェクト独自の対応）
- パッチは `scripts/dlshogi-userdata.sh` の Python スクリプトおよび `scripts/dlshogi-build.sh` で適用

---

### S3 キャッシュと TensorRT バイナリ互換性

TRT のメジャーバージョンが変わると S3 キャッシュのバイナリが動作しなくなる可能性がある。
その場合は S3 キャッシュを手動削除して再デプロイする:

```bash
BUCKET=$(aws cloudformation describe-stacks --stack-name ShogiAiAwsStack \
  --query "Stacks[0].Outputs[?OutputKey=='ArtifactsBucketName'].OutputValue" \
  --output text --region us-east-1)
aws s3 rm "s3://$BUCKET/dlshogi/" --recursive
```

---

### SSM セッションでの LD_LIBRARY_PATH 問題

**現象**: `~/.bashrc` に `export LD_LIBRARY_PATH=...` を追記したのに SSM 経由では反映されない。

```
error while loading shared libraries: libonnxruntime.so.1.11.1: cannot open shared object file
```

**原因**: SSM Session Manager は非インタラクティブシェルで起動するため、`~/.bashrc` が読み込まれない。

**正しい対応**: `/etc/ld.so.conf.d/` にファイルを追加して `ldconfig` を実行する。

```bash
echo "/path/to/lib" | sudo tee /etc/ld.so.conf.d/mylib.conf
sudo ldconfig

# 確認
ldconfig -p | grep <libname>
```

この方法はシステム全体で有効かつ再起動後も維持される。

---

### Spot Instance のデータ消失

**現象**: インスタンスを再起動したらモデルファイルやビルド成果物が消えた。

**原因**: Spot Instance は AWS による中断が発生し、本プロジェクトでは中断時に TERMINATE する設定になっている。EBS ルートボリュームも削除される。

**対策**:
- モデルファイル、ビルド成果物は S3 に置く
- 起動時（userdata）に S3 から取得する設計にする
- ビルド済みバイナリも S3 にキャッシュしておくと起動を高速化できる

---

## dlshogi 系

### TensorRT エンジンのシリアライズ

- dlshogi の初回起動時は ONNX → TensorRT シリアライズが走るため数分かかる
- 完了すると実行ディレクトリに `.serialized` ファイルが生成される
- 2 回目以降は `.serialized` を読み込むため高速

**注意**: `.serialized` が古いバージョンのものだと起動時エラーになる。その場合は削除して再生成。

```bash
rm ~/engines/dlshogi/*.serialized
```

### `parseFromFile` クラッシュ

**原因**: ONNX モデルと TensorRT のバージョン不整合が多い。

**対処**:
1. TensorRT のバージョンを確認して合わせ直す
2. 古い `.serialized` ファイルを削除してから再起動する
3. 公式配布モデルを使う（自作モデルではなく）

---

## ふかうら王 系

### ビルド時の clang++ パス

`make` で `clang++` が見つからない場合は実体のバイナリ名を指定する。

```bash
which clang++        # 見つからない
which clang++-14     # Ubuntu 22.04 で見つかることが多い

# ビルド時に指定
make -j$(nproc) tournament COMPILER=clang++-14 ...
```

### モデルファイル名の注意

- ふかうら王は `eval/model.onnx` というファイル名を探す（名前固定）
- dlshogi リリースのモデルは `model-0000225kai.onnx` のような名前なので **リネーム** が必要

```bash
cp ~/dlshogi_wcsc31/model-0000225kai.onnx ~/engines/fukauraou/eval/model.onnx
```

---

## Windows / ShogiGUI 系

### SSM 経由 SSH でエンジンが見つからない

**現象**: ShogiGUI からエンジンを登録しても起動しない。

**原因**: 接続スクリプト内でエンジンのパスが通っていない、または `ssm-user` で接続しているためホームディレクトリが異なる。

**対処**:
- 起動スクリプト内で `ubuntu` ユーザーとして実行する
- エンジンは絶対パスで指定する（`/home/ubuntu/engines/dlshogi/dlshogi_usi`）
- `cd` で作業ディレクトリを移動してから実行する（モデルを相対パスで参照するエンジンがある）

---

## CDK / 開発系

### `CfnInstance` と `Instance` の違い

本プロジェクトでは `ec2.CfnInstance` を使っている。`ec2.Instance` の高レベル L2 コンストラクトではなく L1 を使っているのは、Spot Instance の設定（`LaunchTemplate` + `spotOptions`）を `CfnInstance` 経由で行う必要があるため。

### SSM パラメータで最新 AMI を自動参照

```typescript
ec2.MachineImage.fromSsmParameter('/aws/service/...', { os: ec2.OperatingSystemType.LINUX })
```

この方法を使うと CDK がデプロイ時に最新の AMI ID を自動解決する。AMI ID をハードコードしない。
