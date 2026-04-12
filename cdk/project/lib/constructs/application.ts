import { Construct } from 'constructs';
import { CfnResource, Stack } from 'aws-cdk-lib';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as firehose from 'aws-cdk-lib/aws-kinesisfirehose';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface ApplicationProps {
  namePrefix: string;
  projectName: string;
  environment: string;
  services: Record<string, { lane: string }>;
  lanes: Record<string, { identifier: string }>;
  vpcId: string;
  privateSubnetIds: string[];
  ecsSecurityGroupId: string;
  dbSecurityGroupId: string;
  albSecurityGroupIds: Record<string, string>;
  logsKmsKeyArn: string;
  s3KmsKeyArn: string;
  dbClusterArn: string;
  dbClusterResourceId: string;
  rdsIamAuthPolicyArn: string;
  s3BucketArns: Record<string, string>;
  s3AccessPolicyArns: Record<string, string>;
  logBucketId: string;
  sharedPrivateSubnetCidrs: string;
  s3PrefixListId?: string;
  containerPort?: number;
}

export class Application extends Construct {
  public readonly cluster: ecs.CfnCluster;
  public readonly ecrRepositories: Record<string, ecr.CfnRepository> = {};
  public readonly taskExecutionRole: iam.CfnRole;
  public readonly taskRoles: Record<string, iam.CfnRole> = {};
  public readonly logGroups: Record<string, logs.CfnLogGroup> = {};

  constructor(scope: Construct, id: string, props: ApplicationProps) {
    super(scope, id);

    const accountId = Stack.of(this).account;
    const region = Stack.of(this).region;
    const containerPort = props.containerPort ?? 80;

    // --------------------------------------------------------------------------------
    // ECS Cluster
    // --------------------------------------------------------------------------------

    this.cluster = new ecs.CfnCluster(this, 'Cluster', {
      clusterName: props.namePrefix,
      clusterSettings: [
        { name: 'containerInsights', value: 'enabled' },
      ],
      capacityProviders: ['FARGATE', 'FARGATE_SPOT'],
      defaultCapacityProviderStrategy: [
        { capacityProvider: 'FARGATE', weight: 1, base: 1 },
        { capacityProvider: 'FARGATE_SPOT', weight: 1 },
      ],
      tags: [{ key: 'Name', value: props.namePrefix }],
    });

    // --------------------------------------------------------------------------------
    // ECR Repositories (per-service)
    // --------------------------------------------------------------------------------

    const lifecyclePolicyKeep10 = JSON.stringify({
      rules: [
        {
          rulePriority: 1,
          description: 'Keep last 10 images',
          selection: {
            tagStatus: 'any',
            countType: 'imageCountMoreThan',
            countNumber: 10,
          },
          action: { type: 'expire' },
        },
      ],
    });

    for (const serviceName of Object.keys(props.services)) {
      const cfnName = toPascalCase(serviceName);
      const repo = new ecr.CfnRepository(this, `Ecr${cfnName}`, {
        repositoryName: `${props.namePrefix}-${serviceName}`,
        imageTagMutability: 'IMMUTABLE',
        imageScanningConfiguration: { scanOnPush: true },
        lifecyclePolicy: { lifecyclePolicyText: lifecyclePolicyKeep10 },
        tags: [{ key: 'Name', value: `${props.namePrefix}-${serviceName}` }],
      });
      this.ecrRepositories[serviceName] = repo;
    }

    // Shared nginx repo
    const nginxRepo = new ecr.CfnRepository(this, 'EcrNginx', {
      repositoryName: `${props.namePrefix}-nginx`,
      imageTagMutability: 'IMMUTABLE',
      imageScanningConfiguration: { scanOnPush: true },
      lifecyclePolicy: { lifecyclePolicyText: lifecyclePolicyKeep10 },
      tags: [{ key: 'Name', value: `${props.namePrefix}-nginx` }],
    });
    this.ecrRepositories['nginx'] = nginxRepo;

    // Shared fluent-bit repo (mutable tags)
    const fluentBitRepo = new ecr.CfnRepository(this, 'EcrFluentBit', {
      repositoryName: `${props.namePrefix}-fluent-bit`,
      imageTagMutability: 'MUTABLE',
      imageScanningConfiguration: { scanOnPush: true },
      tags: [{ key: 'Name', value: `${props.namePrefix}-fluent-bit` }],
    });
    this.ecrRepositories['fluent-bit'] = fluentBitRepo;

    // Pull-through cache rule
    new ecr.CfnPullThroughCacheRule(this, 'PullThroughCache', {
      ecrRepositoryPrefix: 'ecr-public',
      upstreamRegistryUrl: 'public.ecr.aws',
    });

    // --------------------------------------------------------------------------------
    // IAM - Task Execution Role (shared)
    // --------------------------------------------------------------------------------

    this.taskExecutionRole = new iam.CfnRole(this, 'TaskExecutionRole', {
      roleName: `${props.namePrefix}-task-execution`,
      assumeRolePolicyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Principal: { Service: 'ecs-tasks.amazonaws.com' },
            Action: 'sts:AssumeRole',
          },
        ],
      },
      managedPolicyArns: [
        'arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy',
      ],
      policies: [
        {
          policyName: 'ssm-parameter-access',
          policyDocument: {
            Version: '2012-10-17',
            Statement: [
              {
                Effect: 'Allow',
                Action: ['ssm:GetParameters', 'ssm:GetParameter'],
                Resource: `arn:aws:ssm:${region}:${accountId}:parameter/${props.projectName}/${props.environment}/*`,
              },
              {
                Effect: 'Allow',
                Action: 'kms:Decrypt',
                Resource: props.logsKmsKeyArn,
              },
            ],
          },
        },
        {
          policyName: 'ecr-pull-through-cache',
          policyDocument: {
            Version: '2012-10-17',
            Statement: [
              {
                Effect: 'Allow',
                Action: ['ecr:CreateRepository', 'ecr:BatchImportUpstreamImage'],
                Resource: `arn:aws:ecr:${region}:${accountId}:repository/ecr-public/*`,
              },
            ],
          },
        },
      ],
      tags: [{ key: 'Name', value: `${props.namePrefix}-task-execution` }],
    });

    // --------------------------------------------------------------------------------
    // IAM - Task Roles (per-service)
    // --------------------------------------------------------------------------------

    const auditBucketName = `${props.namePrefix}-audit-logs-${accountId}`;
    const auditBucketArn = `arn:aws:s3:::${auditBucketName}`;

    for (const [serviceName, serviceConf] of Object.entries(props.services)) {
      const cfnName = toPascalCase(serviceName);
      const logGroupArn = `arn:aws:logs:${region}:${accountId}:log-group:/ecs/${props.namePrefix}/${serviceName}:*`;
      const firehoseArn = `arn:aws:firehose:${region}:${accountId}:deliverystream/${props.namePrefix}-audit-logs`;

      const taskRole = new iam.CfnRole(this, `TaskRole${cfnName}`, {
        roleName: `${props.namePrefix}-${serviceName}-task`,
        assumeRolePolicyDocument: {
          Version: '2012-10-17',
          Statement: [
            {
              Effect: 'Allow',
              Principal: { Service: 'ecs-tasks.amazonaws.com' },
              Action: 'sts:AssumeRole',
            },
          ],
        },
        managedPolicyArns: [
          props.rdsIamAuthPolicyArn,
          props.s3AccessPolicyArns[serviceConf.lane],
        ],
        policies: [
          {
            policyName: 'firelens-access',
            policyDocument: {
              Version: '2012-10-17',
              Statement: [
                {
                  Effect: 'Allow',
                  Action: [
                    'logs:CreateLogStream',
                    'logs:PutLogEvents',
                    'logs:DescribeLogStreams',
                  ],
                  Resource: logGroupArn,
                },
                {
                  Effect: 'Allow',
                  Action: 'firehose:PutRecordBatch',
                  Resource: firehoseArn,
                },
                {
                  Effect: 'Allow',
                  Action: ['s3:GetObject', 's3:GetBucketLocation'],
                  Resource: [auditBucketArn, `${auditBucketArn}/fluent-bit/*`],
                },
                {
                  Effect: 'Allow',
                  Action: 'kms:Decrypt',
                  Resource: props.s3KmsKeyArn,
                },
              ],
            },
          },
        ],
        tags: [{ key: 'Name', value: `${props.namePrefix}-${serviceName}-task` }],
      });
      this.taskRoles[serviceName] = taskRole;
    }

    // --------------------------------------------------------------------------------
    // CloudWatch Log Groups (per-service)
    // --------------------------------------------------------------------------------

    for (const serviceName of Object.keys(props.services)) {
      const cfnName = toPascalCase(serviceName);
      const logGroup = new logs.CfnLogGroup(this, `LogGroup${cfnName}`, {
        logGroupName: `/ecs/${props.namePrefix}/${serviceName}`,
        retentionInDays: 30,
        kmsKeyId: props.logsKmsKeyArn,
        tags: [{ key: 'Name', value: `${props.namePrefix}-${serviceName}` }],
      });
      this.logGroups[serviceName] = logGroup;
    }

    // --------------------------------------------------------------------------------
    // Audit Logs S3 Bucket
    // --------------------------------------------------------------------------------

    const auditBucket = new s3.CfnBucket(this, 'AuditLogsBucket', {
      bucketName: auditBucketName,
      versioningConfiguration: { status: 'Enabled' },
      bucketEncryption: {
        serverSideEncryptionConfiguration: [
          {
            serverSideEncryptionByDefault: {
              sseAlgorithm: 'aws:kms',
              kmsMasterKeyId: props.s3KmsKeyArn,
            },
            bucketKeyEnabled: true,
          },
        ],
      },
      publicAccessBlockConfiguration: {
        blockPublicAcls: true,
        blockPublicPolicy: true,
        ignorePublicAcls: true,
        restrictPublicBuckets: true,
      },
      loggingConfiguration: {
        destinationBucketName: props.logBucketId,
        logFilePrefix: 'audit-logs/',
      },
      lifecycleConfiguration: {
        rules: [
          {
            id: 'archive-and-expire',
            status: 'Enabled',
            prefix: 'audit/',
            transitions: [
              { storageClass: 'GLACIER', transitionInDays: 90 },
            ],
            expirationInDays: 365,
          },
        ],
      },
      tags: [{ key: 'Name', value: `${props.namePrefix}-audit-logs` }],
    });

    new s3.CfnBucketPolicy(this, 'AuditLogsBucketPolicy', {
      bucket: auditBucket.ref,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Sid: 'DenyInsecureTransport',
            Effect: 'Deny',
            Principal: '*',
            Action: 's3:*',
            Resource: [auditBucketArn, `${auditBucketArn}/*`],
            Condition: {
              Bool: { 'aws:SecureTransport': 'false' },
            },
          },
        ],
      },
    });

    // --------------------------------------------------------------------------------
    // Kinesis Data Firehose Delivery Stream
    // --------------------------------------------------------------------------------

    const firehoseRole = new iam.CfnRole(this, 'FirehoseRole', {
      roleName: `${props.namePrefix}-firehose-audit`,
      assumeRolePolicyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Principal: { Service: 'firehose.amazonaws.com' },
            Action: 'sts:AssumeRole',
          },
        ],
      },
      policies: [
        {
          policyName: 'firehose-s3-access',
          policyDocument: {
            Version: '2012-10-17',
            Statement: [
              {
                Effect: 'Allow',
                Action: [
                  's3:AbortMultipartUpload',
                  's3:GetBucketLocation',
                  's3:GetObject',
                  's3:ListBucket',
                  's3:ListBucketMultipartUploads',
                  's3:PutObject',
                ],
                Resource: [auditBucketArn, `${auditBucketArn}/*`],
              },
              {
                Effect: 'Allow',
                Action: ['kms:Decrypt', 'kms:GenerateDataKey'],
                Resource: props.s3KmsKeyArn,
              },
            ],
          },
        },
      ],
      tags: [{ key: 'Name', value: `${props.namePrefix}-firehose-audit` }],
    });

    new firehose.CfnDeliveryStream(this, 'AuditLogsFirehose', {
      deliveryStreamName: `${props.namePrefix}-audit-logs`,
      deliveryStreamType: 'DirectPut',
      extendedS3DestinationConfiguration: {
        roleArn: firehoseRole.attrArn,
        bucketArn: auditBucketArn,
        prefix: 'audit/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/',
        errorOutputPrefix: 'audit-errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/',
        bufferingHints: { sizeInMBs: 5, intervalInSeconds: 60 },
        compressionFormat: 'GZIP',
        encryptionConfiguration: {
          kmsEncryptionConfig: { awskmsKeyArn: props.s3KmsKeyArn },
        },
      },
      tags: [{ key: 'Name', value: `${props.namePrefix}-audit-logs` }],
    });

    // --------------------------------------------------------------------------------
    // Security Group Rules
    // --------------------------------------------------------------------------------

    // Ingress from ALB SGs (per lane) to ECS on container port
    for (const [laneName, albSgId] of Object.entries(props.albSecurityGroupIds)) {
      const cfnLane = toPascalCase(laneName);
      new ec2.CfnSecurityGroupIngress(this, `SgIngressAlb${cfnLane}`, {
        groupId: props.ecsSecurityGroupId,
        ipProtocol: 'tcp',
        fromPort: containerPort,
        toPort: containerPort,
        sourceSecurityGroupId: albSgId,
        description: `From ${laneName} ALB`,
      });
    }

    // Egress to DB on PostgreSQL (5432)
    new ec2.CfnSecurityGroupEgress(this, 'SgEgressDb', {
      groupId: props.ecsSecurityGroupId,
      ipProtocol: 'tcp',
      fromPort: 5432,
      toPort: 5432,
      destinationSecurityGroupId: props.dbSecurityGroupId,
      description: 'To Aurora PostgreSQL',
    });

    // Egress HTTPS to S3 prefix list
    if (props.s3PrefixListId) {
      new ec2.CfnSecurityGroupEgress(this, 'SgEgressS3', {
        groupId: props.ecsSecurityGroupId,
        ipProtocol: 'tcp',
        fromPort: 443,
        toPort: 443,
        destinationPrefixListId: props.s3PrefixListId,
        description: 'HTTPS to S3 via gateway endpoint',
      });
    }

    // Egress HTTPS to shared VPC CIDRs (for VPC endpoints via TGW)
    new ec2.CfnSecurityGroupEgress(this, 'SgEgressVpce', {
      groupId: props.ecsSecurityGroupId,
      ipProtocol: 'tcp',
      fromPort: 443,
      toPort: 443,
      cidrIp: props.sharedPrivateSubnetCidrs,
      description: 'HTTPS to shared VPC endpoints via TGW',
    });

    // --------------------------------------------------------------------------------
    // Amazon Inspector (ECR scanning filter)
    // Note: Inspector2 enablement (aws_inspector2_enabler) has no CloudFormation
    // equivalent. Enable via CLI/console: aws inspector2 enable --resource-types ECR
    // The filter below configures scan criteria for ECR images.
    // --------------------------------------------------------------------------------

    new CfnResource(this, 'InspectorFilter', {
      type: 'AWS::InspectorV2::Filter',
      properties: {
        Name: `${props.namePrefix}-ecr-scan`,
        Description: 'ECR container image scan filter',
        FilterAction: 'NONE',
        FilterCriteria: {
          ResourceType: [{ Comparison: 'EQUALS', Value: 'AWS_ECR_CONTAINER_IMAGE' }],
        },
      },
    });
  }
}

// --------------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------------

function toPascalCase(s: string): string {
  return s
    .split('-')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}
