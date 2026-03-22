@echo off
set KEY="C:\Program Files (x86)\ShogiGUI\shogi-ai-keypair.pem"
set INSTANCE_ID=i-0d25fe44c6a0013aa
set USER=ssm-user

@REM ssh -i %KEY% -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o "ProxyCommand=aws ssm start-session --target %INSTANCE_ID% --document-name AWS-StartSSHSession --parameters portNumber=22 --region us-east-1" %USER%@%INSTANCE_ID% "cd /opt/DeepLearningShogi/usi/bin && ./usi"

@REM ssh -i %KEY% ubuntu@.amazonaws.com

ssh -i %KEY% -o StrictHostKeyChecking=no  -o ServerAliveInterval=15 ubuntu@e /opt/DeepLearningShogi/usi/bin/usi
