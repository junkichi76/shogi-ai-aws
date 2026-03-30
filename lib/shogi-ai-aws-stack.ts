import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as fs from 'fs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as path from 'path';
import * as s3 from 'aws-cdk-lib/aws-s3';

export class ShogiAiAwsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // デプロイするエンジンを context で指定する
    // 使用例:
    //   cdk deploy -c engine=fukauraou  → fukauraou のみ
    //   cdk deploy -c engine=dlshogi    → dlshogi のみ
    //   cdk deploy -c engine=both       → 両方 (デフォルト)
    //   cdk deploy -c engine=none       → デプロイしない
    const engine = this.node.tryGetContext('engine') ?? 'both';

    const deployFukauraou = engine === 'fukauraou' || engine === 'both';
    const deployDlshogi = engine === 'dlshogi' || engine === 'both';

    // S3バケット: ビルド済みバイナリとモデルファイルをキャッシュする（Spot中断後の再起動を高速化）
    const artifactsBucket = new s3.Bucket(this, 'DlshogiArtifacts', {
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: false,
    });

    const dlshogiRawScript = fs.readFileSync(
      path.join(__dirname, '..', 'scripts', 'dlshogi-userdata.sh'),
      'utf8'
    );
    // シェバン行の直後にバケット名を環境変数として注入する
    const dlshogiUserDataScript = dlshogiRawScript.replace(
      '#!/bin/bash\n',
      `#!/bin/bash\nexport ARTIFACTS_BUCKET="${artifactsBucket.bucketName}"\n`
    );

    // VPC
    // restrictDefaultSecurityGroup: false — デフォルト SG 制限の Lambda カスタムリソースを無効化。
    // ec2:AuthorizeSecurityGroupIngress が SCP で制限されている環境ではデプロイが失敗するため。
    const vpc = new ec2.Vpc(this, 'ShogiAiVpc', {
      ipAddresses: ec2.IpAddresses.cidr('172.16.0.0/16'),
      maxAzs: 1,
      restrictDefaultSecurityGroup: false,
      subnetConfiguration: [
        {
          name: 'PublicSubnet',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
      ],
    });

    const keyPair = ec2.KeyPair.fromKeyPairName(this, 'KeyPair', 'shogi-ai-keypair');
    const publicSubnet = vpc.publicSubnets[0];

    const createSpotInstance = (
      id: string,
      machineImage: ec2.IMachineImage,
      userData?: ec2.UserData,
      rootVolumeSizeGiB: number = 8,
      additionalVolumeSizeGiB?: number,
      additionalPolicies?: iam.PolicyStatement[]
    ) => {
      const securityGroup = new ec2.SecurityGroup(this, `${id}SecurityGroup`, {
        vpc,
        allowAllOutbound: true,
      });

      const role = new iam.Role(this, `${id}Role`, {
        assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        ],
      });

      for (const policy of additionalPolicies ?? []) {
        role.addToPolicy(policy);
      }

      const launchTemplate = new ec2.LaunchTemplate(this, `${id}LaunchTemplate`, {
        instanceType: ec2.InstanceType.of(ec2.InstanceClass.G4DN, ec2.InstanceSize.XLARGE),
        machineImage,
        keyPair,
        role,
        securityGroup,
        userData,
        blockDevices: [
          {
            deviceName: '/dev/sda1',
            volume: ec2.BlockDeviceVolume.ebs(rootVolumeSizeGiB),
          },
          ...(additionalVolumeSizeGiB
            ? [
                {
                  deviceName: '/dev/sdf',
                  volume: ec2.BlockDeviceVolume.ebs(additionalVolumeSizeGiB),
                },
              ]
            : []),
        ],
        spotOptions: {
          interruptionBehavior: ec2.SpotInstanceInterruption.TERMINATE,
        },
      });

      return new ec2.CfnInstance(this, id, {
        launchTemplate: {
          launchTemplateId: launchTemplate.launchTemplateId,
          version: launchTemplate.versionNumber,
        },
        subnetId: publicSubnet.subnetId,
      });
    };

    if (deployFukauraou) {
      const fukauraouInstance = createSpotInstance(
        'FukauraOU',
        ec2.MachineImage.fromSsmParameter(
          '/aws/service/canonical/ubuntu/server/20.04/stable/current/amd64/hvm/ebs-gp2/ami-id',
          { os: ec2.OperatingSystemType.LINUX }
        )
      );

      new cdk.CfnOutput(this, 'FukauraOUInstanceId', {
        value: fukauraouInstance.ref,
        description: 'FukauraOU EC2 instance ID',
      });

      new cdk.CfnOutput(this, 'FukauraOUPublicIp', {
        value: fukauraouInstance.attrPublicIp,
        description: 'FukauraOU EC2 public IP address',
      });
    }

    if (deployDlshogi) {
      // 参照: https://github.com/TadaoYamaoka/DeepLearningShogi/wiki
      const dlshogiInstance = createSpotInstance(
        'dlshogi',
        ec2.MachineImage.fromSsmParameter(
          '/aws/service/deeplearning/ami/x86_64/oss-nvidia-driver-gpu-pytorch-2.7-ubuntu-22.04/latest/ami-id',
          { os: ec2.OperatingSystemType.LINUX }
        ),
        ec2.UserData.custom(dlshogiUserDataScript),
        100,
        undefined,
        [
          new iam.PolicyStatement({
            actions: ['s3:GetObject', 's3:PutObject', 's3:ListBucket'],
            resources: [
              artifactsBucket.bucketArn,
              `${artifactsBucket.bucketArn}/*`,
            ],
          }),
        ]
      );

      new cdk.CfnOutput(this, 'DlshogiInstanceId', {
        value: dlshogiInstance.ref,
        description: 'dlshogi EC2 instance ID',
      });

      new cdk.CfnOutput(this, 'DlshogiPublicIp', {
        value: dlshogiInstance.attrPublicIp,
        description: 'dlshogi EC2 public IP address',
      });
    }

    new cdk.CfnOutput(this, 'ArtifactsBucketName', {
      value: artifactsBucket.bucketName,
      description: 'S3 bucket for dlshogi build artifacts and model files',
    });
  }
}
