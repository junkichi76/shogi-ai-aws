@echo off
@REM ShogiGUI 用 dlshogi エンジン起動スクリプト (SSH over SSM)
@REM ShogiGUI の「エンジン管理」でこの .cmd ファイルを登録してください。

set KEY="C:\Users\akiya\shogi-ai-keypair.pem"
set STACK_NAME=ShogiAiAwsStack
set REGION=us-east-1
set ENGINE=dlshogi_usi

@REM session-manager-plugin を PATH に追加（ShogiGUI は System PATH を継承しない場合がある）
set PATH=%PATH%;C:\Program Files\Amazon\SessionManagerPlugin\bin;C:\Program Files\Amazon\AWSCLIV2

@REM CDK スタック出力からインスタンス ID を動的に取得（デプロイ毎に変わるためハードコードしない）
aws cloudformation describe-stacks --stack-name %STACK_NAME% --query "Stacks[0].Outputs[?OutputKey=='DlshogiInstanceId'].OutputValue" --output text --region %REGION% > "%TEMP%\dlshogi_instance_id.tmp" 2>nul
set /p INSTANCE_ID=<"%TEMP%\dlshogi_instance_id.tmp"
del "%TEMP%\dlshogi_instance_id.tmp" 2>nul

if "%INSTANCE_ID%"=="" (
    echo ERROR: dlshogi インスタンス ID を取得できませんでした。CDK でデプロイされているか確認してください。>&2
    exit /b 1
)

ssh -i %KEY% ^
    -o StrictHostKeyChecking=no ^
    -o UserKnownHostsFile=NUL ^
    -o ServerAliveInterval=15 ^
    -o ServerAliveCountMax=3 ^
    -o "ProxyCommand=aws ssm start-session --target %INSTANCE_ID% --document-name AWS-StartSSHSession --parameters portNumber=22 --region %REGION%" ^
    ubuntu@%INSTANCE_ID% %ENGINE%
