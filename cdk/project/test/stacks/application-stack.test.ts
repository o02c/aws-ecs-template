import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { ApplicationStack } from '../../lib/stacks/application-stack';
import { ProjectConfig } from '../../lib/helpers/config-types';

const testConfig: ProjectConfig = {
  account: { accountId: '123456789012', region: 'ap-northeast-1' },
  projectName: 'myapp',
  environment: 'dev',
  vpcCidr: '10.1.0.0/16',
  azs: ['ap-northeast-1a', 'ap-northeast-1c'],
  privateSubnets: {
    'ap-northeast-1a': '10.1.11.0/24',
    'ap-northeast-1c': '10.1.12.0/24',
  },
  domainName: 'example.com',
  lanes: {
    user: { identifier: 'user' },
    admin: { identifier: 'admin' },
  },
  services: {
    'user-api': { lane: 'user' },
    'admin-api': { lane: 'admin' },
  },
  database: {
    deletionProtection: false,
    skipFinalSnapshot: true,
  },
  enableCicd: false,
  enableDnsFirewall: true,
  deployMode: 'cdk-deploy',
};

describe('ApplicationStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new ApplicationStack(app, 'TestApplicationStack', {
      config: testConfig,
      env: { account: testConfig.account.accountId, region: testConfig.account.region },
    });
    template = Template.fromStack(stack);
  });

  // --------------------------------------------------------------------------------
  // ECS Cluster
  // --------------------------------------------------------------------------------

  test('creates ECS Cluster with Container Insights enabled', () => {
    template.hasResourceProperties('AWS::ECS::Cluster', {
      ClusterName: 'myapp-dev',
      ClusterSettings: [
        { Name: 'containerInsights', Value: 'enabled' },
      ],
    });
  });

  test('creates ECS Cluster with Fargate capacity providers', () => {
    template.hasResourceProperties('AWS::ECS::Cluster', {
      CapacityProviders: ['FARGATE', 'FARGATE_SPOT'],
      DefaultCapacityProviderStrategy: Match.arrayWith([
        Match.objectLike({ CapacityProvider: 'FARGATE', Base: 1, Weight: 1 }),
        Match.objectLike({ CapacityProvider: 'FARGATE_SPOT', Weight: 1 }),
      ]),
    });
  });

  // --------------------------------------------------------------------------------
  // ECR Repositories
  // --------------------------------------------------------------------------------

  test('creates ECR repositories for each service with immutable tags', () => {
    template.hasResourceProperties('AWS::ECR::Repository', {
      RepositoryName: 'myapp-dev-user-api',
      ImageTagMutability: 'IMMUTABLE',
      ImageScanningConfiguration: { ScanOnPush: true },
    });
    template.hasResourceProperties('AWS::ECR::Repository', {
      RepositoryName: 'myapp-dev-admin-api',
      ImageTagMutability: 'IMMUTABLE',
      ImageScanningConfiguration: { ScanOnPush: true },
    });
  });

  test('creates shared nginx ECR repository with immutable tags', () => {
    template.hasResourceProperties('AWS::ECR::Repository', {
      RepositoryName: 'myapp-dev-nginx',
      ImageTagMutability: 'IMMUTABLE',
      ImageScanningConfiguration: { ScanOnPush: true },
    });
  });

  test('creates shared fluent-bit ECR repository with mutable tags', () => {
    template.hasResourceProperties('AWS::ECR::Repository', {
      RepositoryName: 'myapp-dev-fluent-bit',
      ImageTagMutability: 'MUTABLE',
      ImageScanningConfiguration: { ScanOnPush: true },
    });
  });

  test('creates ECR repositories with lifecycle policy (keep last 10)', () => {
    template.hasResourceProperties('AWS::ECR::Repository', {
      RepositoryName: 'myapp-dev-user-api',
      LifecyclePolicy: Match.objectLike({
        LifecyclePolicyText: Match.stringLikeRegexp('imageCountMoreThan'),
      }),
    });
  });

  test('creates ECR pull-through cache rule', () => {
    template.hasResourceProperties('AWS::ECR::PullThroughCacheRule', {
      EcrRepositoryPrefix: 'ecr-public',
      UpstreamRegistryUrl: 'public.ecr.aws',
    });
  });

  // --------------------------------------------------------------------------------
  // IAM - Task Execution Role
  // --------------------------------------------------------------------------------

  test('creates Task Execution Role with ECS assume role policy', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'myapp-dev-task-execution',
      AssumeRolePolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Effect: 'Allow',
            Principal: { Service: 'ecs-tasks.amazonaws.com' },
            Action: 'sts:AssumeRole',
          }),
        ]),
      }),
      ManagedPolicyArns: Match.arrayWith([
        'arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy',
      ]),
    });
  });

  test('Task Execution Role has SSM and KMS permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'myapp-dev-task-execution',
      Policies: Match.arrayWith([
        Match.objectLike({
          PolicyName: 'ssm-parameter-access',
          PolicyDocument: Match.objectLike({
            Statement: Match.arrayWith([
              Match.objectLike({
                Action: ['ssm:GetParameters', 'ssm:GetParameter'],
              }),
            ]),
          }),
        }),
      ]),
    });
  });

  test('Task Execution Role has ECR pull-through cache permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'myapp-dev-task-execution',
      Policies: Match.arrayWith([
        Match.objectLike({
          PolicyName: 'ecr-pull-through-cache',
          PolicyDocument: Match.objectLike({
            Statement: Match.arrayWith([
              Match.objectLike({
                Action: ['ecr:CreateRepository', 'ecr:BatchImportUpstreamImage'],
              }),
            ]),
          }),
        }),
      ]),
    });
  });

  // --------------------------------------------------------------------------------
  // IAM - Task Roles (per-service)
  // --------------------------------------------------------------------------------

  test('creates Task Roles for each service', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'myapp-dev-user-api-task',
      AssumeRolePolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Principal: { Service: 'ecs-tasks.amazonaws.com' },
          }),
        ]),
      }),
    });
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'myapp-dev-admin-api-task',
    });
  });

  test('Task Roles have FireLens access policy', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'myapp-dev-user-api-task',
      Policies: Match.arrayWith([
        Match.objectLike({
          PolicyName: 'firelens-access',
          PolicyDocument: Match.objectLike({
            Statement: Match.arrayWith([
              Match.objectLike({
                Action: ['logs:CreateLogStream', 'logs:PutLogEvents', 'logs:DescribeLogStreams'],
              }),
              Match.objectLike({
                Action: 'firehose:PutRecordBatch',
              }),
            ]),
          }),
        }),
      ]),
    });
  });

  // --------------------------------------------------------------------------------
  // CloudWatch Log Groups
  // --------------------------------------------------------------------------------

  test('creates CloudWatch Log Groups for each service', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/ecs/myapp-dev/user-api',
      RetentionInDays: 30,
    });
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/ecs/myapp-dev/admin-api',
      RetentionInDays: 30,
    });
  });

  test('Log Groups are KMS encrypted', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/ecs/myapp-dev/user-api',
      KmsKeyId: Match.anyValue(),
    });
  });

  // --------------------------------------------------------------------------------
  // Audit Logs S3 Bucket
  // --------------------------------------------------------------------------------

  test('creates audit logs S3 bucket with KMS encryption', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: 'myapp-dev-audit-logs-123456789012',
      VersioningConfiguration: { Status: 'Enabled' },
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          Match.objectLike({
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'aws:kms',
            },
          }),
        ],
      },
    });
  });

  test('audit logs bucket has public access block', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: 'myapp-dev-audit-logs-123456789012',
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
  });

  test('audit logs bucket has lifecycle rule (90d GLACIER, 365d expire)', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: 'myapp-dev-audit-logs-123456789012',
      LifecycleConfiguration: {
        Rules: [
          Match.objectLike({
            Id: 'archive-and-expire',
            Status: 'Enabled',
            Transitions: [
              { StorageClass: 'GLACIER', TransitionInDays: 90 },
            ],
            ExpirationInDays: 365,
          }),
        ],
      },
    });
  });

  test('audit logs bucket policy denies insecure transport', () => {
    template.hasResourceProperties('AWS::S3::BucketPolicy', {
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Sid: 'DenyInsecureTransport',
            Effect: 'Deny',
          }),
        ]),
      }),
    });
  });

  // --------------------------------------------------------------------------------
  // Kinesis Data Firehose
  // --------------------------------------------------------------------------------

  test('creates Firehose delivery stream for audit logs', () => {
    template.hasResourceProperties('AWS::KinesisFirehose::DeliveryStream', {
      DeliveryStreamName: 'myapp-dev-audit-logs',
      DeliveryStreamType: 'DirectPut',
      ExtendedS3DestinationConfiguration: Match.objectLike({
        CompressionFormat: 'GZIP',
        BufferingHints: { SizeInMBs: 5, IntervalInSeconds: 60 },
      }),
    });
  });

  test('creates Firehose IAM role', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'myapp-dev-firehose-audit',
      AssumeRolePolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Principal: { Service: 'firehose.amazonaws.com' },
          }),
        ]),
      }),
    });
  });

  // --------------------------------------------------------------------------------
  // Security Group Rules
  // --------------------------------------------------------------------------------

  test('creates SG ingress rules from ALB to ECS per lane', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroupIngress', {
      IpProtocol: 'tcp',
      FromPort: 80,
      ToPort: 80,
      Description: 'From user ALB',
    });
    template.hasResourceProperties('AWS::EC2::SecurityGroupIngress', {
      IpProtocol: 'tcp',
      FromPort: 80,
      ToPort: 80,
      Description: 'From admin ALB',
    });
  });

  test('creates SG egress rule to DB on port 5432', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroupEgress', {
      IpProtocol: 'tcp',
      FromPort: 5432,
      ToPort: 5432,
      Description: 'To Aurora PostgreSQL',
    });
  });

  test('creates SG egress rule to shared VPC endpoints', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroupEgress', {
      IpProtocol: 'tcp',
      FromPort: 443,
      ToPort: 443,
      Description: 'HTTPS to shared VPC endpoints via TGW',
    });
  });

  // --------------------------------------------------------------------------------
  // Amazon Inspector
  // --------------------------------------------------------------------------------

  test('creates Inspector ECR scan filter', () => {
    template.hasResourceProperties('AWS::InspectorV2::Filter', {
      Name: 'myapp-dev-ecr-scan',
      FilterAction: 'NONE',
      FilterCriteria: {
        ResourceType: [{ Comparison: 'EQUALS', Value: 'AWS_ECR_CONTAINER_IMAGE' }],
      },
    });
  });

  // --------------------------------------------------------------------------------
  // SSM Parameters
  // --------------------------------------------------------------------------------

  test('creates SSM Parameter for ECS cluster name', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/ecs-cluster-name',
    });
  });

  test('creates SSM Parameters for ECR repository URLs', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/ecr/user-api/url',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/ecr/admin-api/url',
    });
  });

  test('creates SSM Parameter for task execution role ARN', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/task-execution-role-arn',
    });
  });

  test('creates SSM Parameters for task role ARNs', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/task-role/user-api/arn',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/task-role/admin-api/arn',
    });
  });
});
