import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as fs from 'fs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as path from 'path';

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
    const dlshogiUserDataScript = fs.readFileSync(
      path.join(__dirname, '..', 'scripts', 'dlshogi-userdata.sh'),
      'utf8'
    );

    // VPC
    const vpc = new ec2.Vpc(this, 'ShogiAiVpc', {
      ipAddresses: ec2.IpAddresses.cidr('192.168.0.0/16'),
      maxAzs: 1,
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
      additionalVolumeSizeGiB?: number
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

      new ec2.CfnInstance(this, id, {
        launchTemplate: {
          launchTemplateId: launchTemplate.launchTemplateId,
          version: launchTemplate.versionNumber,
        },
        subnetId: publicSubnet.subnetId,
      });
    };

    if (deployFukauraou) {
      createSpotInstance(
        'FukauraOU',
        ec2.MachineImage.fromSsmParameter(
          '/aws/service/canonical/ubuntu/server/20.04/stable/current/amd64/hvm/ebs-gp2/ami-id',
          { os: ec2.OperatingSystemType.LINUX }
        )
      );
    }

    if (deployDlshogi) {
      // 参照: https://github.com/TadaoYamaoka/DeepLearningShogi/wiki
      createSpotInstance(
        'dlshogi',
        ec2.MachineImage.fromSsmParameter(
          '/aws/service/deeplearning/ami/x86_64/oss-nvidia-driver-gpu-pytorch-2.7-ubuntu-22.04/latest/ami-id',
          { os: ec2.OperatingSystemType.LINUX }
        ),
        ec2.UserData.custom(dlshogiUserDataScript),
        100
      );
    }

    // const bucket = new cdk.aws_s3.Bucket(this, 'ShogiAiBucket', {
    //   bucketName: `shogi-ai-bucket-${cdk.Stack.of(this).account}`,
    //   removalPolicy: cdk.RemovalPolicy.DESTROY,
    //   autoDeleteObjects: true,
    // });

    // bucket.grantRead(ec2Instance.role);
  }
}
