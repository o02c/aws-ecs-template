import * as cdk from 'aws-cdk-lib';
import { Stack, StackProps, Fn } from 'aws-cdk-lib';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';
import { ProjectConfig } from '../helpers/config-types';
import { ProjectVpc } from '../constructs/project-vpc';
import { SecurityGroupSet } from '../constructs/security-group-set';
import { HostedZone } from '../constructs/hosted-zone';
import { DnsFirewall } from '../constructs/dns-firewall';
import { putSsmParameter, sharedSsmParameterName } from '../helpers/ssm';

export interface FoundationStackProps extends StackProps {
  config: ProjectConfig;
}

export class FoundationStack extends Stack {
  constructor(scope: Construct, id: string, props: FoundationStackProps) {
    super(scope, id, props);

    const { config } = props;
    const prefix = `${config.projectName}-${config.environment}`;
    const region = config.account.region;
    const accountId = config.account.accountId;

    // --------------------------------------------------------------------------------
    // KMS Keys (rds, s3, logs, secrets)
    // --------------------------------------------------------------------------------

    const kmsKeys: Record<string, kms.Key> = {};
    const kmsKeyDefs: Record<string, { description: string; service: string | null }> = {
      rds: { description: 'CMK for Aurora encryption', service: null },
      s3: { description: 'CMK for S3 bucket encryption', service: null },
      logs: { description: 'CMK for CloudWatch Logs encryption', service: `logs.${region}.amazonaws.com` },
      secrets: { description: 'CMK for Secrets Manager encryption', service: null },
    };

    for (const [keyName, def] of Object.entries(kmsKeyDefs)) {
      const cfnKeyName = capitalize(keyName);
      const key = new kms.Key(this, `Kms${cfnKeyName}`, {
        description: def.description,
        enableKeyRotation: true,
        alias: `alias/${prefix}-${keyName}`,
      });
      const cfnKey = key.node.defaultChild as kms.CfnKey;
      cfnKey.pendingWindowInDays = 30;

      if (def.service) {
        key.addToResourcePolicy(
          new iam.PolicyStatement({
            sid: 'AllowServicePrincipal',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal(def.service)],
            actions: [
              'kms:Encrypt',
              'kms:Decrypt',
              'kms:ReEncrypt*',
              'kms:GenerateDataKey*',
              'kms:DescribeKey',
            ],
            resources: ['*'],
            conditions: {
              ArnLike: {
                'kms:EncryptionContext:aws:logs:arn': `arn:aws:logs:${region}:${accountId}:log-group:*`,
              },
            },
          }),
        );
      }

      kmsKeys[keyName] = key;
    }

    // --------------------------------------------------------------------------------
    // Logging S3 Bucket (access logs)
    // --------------------------------------------------------------------------------

    const loggingBucket = new s3.CfnBucket(this, 'LoggingBucket', {
      bucketName: `${prefix}-access-logs-${accountId}`,
      versioningConfiguration: { status: 'Enabled' },
      bucketEncryption: {
        serverSideEncryptionConfiguration: [
          {
            serverSideEncryptionByDefault: {
              sseAlgorithm: 'AES256',
            },
          },
        ],
      },
      ownershipControls: {
        rules: [{ objectOwnership: 'BucketOwnerPreferred' }],
      },
      publicAccessBlockConfiguration: {
        blockPublicAcls: true,
        blockPublicPolicy: true,
        ignorePublicAcls: true,
        restrictPublicBuckets: true,
      },
      lifecycleConfiguration: {
        rules: [
          {
            id: 'archive-and-expire',
            status: 'Enabled',
            transitions: [
              {
                storageClass: 'GLACIER',
                transitionInDays: 90,
              },
            ],
            expirationInDays: 365,
          },
        ],
      },
      tags: [{ key: 'Name', value: `${prefix}-access-logs` }],
    });

    // ELB account IDs per region for ALB access logging
    const elbAccountIds: Record<string, string> = {
      'us-east-1': '127311923021',
      'us-east-2': '033677994240',
      'us-west-1': '027434742980',
      'us-west-2': '797873946194',
      'ap-east-1': '754344448648',
      'ap-south-1': '718504428378',
      'ap-northeast-1': '582318560864',
      'ap-northeast-2': '600734575887',
      'ap-northeast-3': '383597477331',
      'ap-southeast-1': '114774131450',
      'ap-southeast-2': '783225319266',
      'ca-central-1': '985666609251',
      'eu-central-1': '054676820928',
      'eu-west-1': '156460612806',
      'eu-west-2': '652711504416',
      'eu-west-3': '009996457667',
      'eu-north-1': '897822967062',
      'sa-east-1': '507241528517',
    };

    const bucketArn = `arn:aws:s3:::${prefix}-access-logs-${accountId}`;
    const elbAccountId = elbAccountIds[region] ?? elbAccountIds['ap-northeast-1'];

    new s3.CfnBucketPolicy(this, 'LoggingBucketPolicy', {
      bucket: loggingBucket.ref,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Sid: 'AllowCloudFrontLogDelivery',
            Effect: 'Allow',
            Principal: { Service: 'delivery.logs.amazonaws.com' },
            Action: 's3:PutObject',
            Resource: `${bucketArn}/cloudfront/*`,
            Condition: {
              StringEquals: { 's3:x-amz-acl': 'bucket-owner-full-control' },
            },
          },
          {
            Sid: 'AllowCloudFrontLogDeliveryAclCheck',
            Effect: 'Allow',
            Principal: { Service: 'delivery.logs.amazonaws.com' },
            Action: 's3:GetBucketAcl',
            Resource: bucketArn,
          },
          {
            Sid: 'AllowALBLogDelivery',
            Effect: 'Allow',
            Principal: { AWS: `arn:aws:iam::${elbAccountId}:root` },
            Action: 's3:PutObject',
            Resource: `${bucketArn}/alb/*`,
            Condition: {
              StringEquals: { 's3:x-amz-acl': 'bucket-owner-full-control' },
            },
          },
          {
            Sid: 'AllowS3LogDelivery',
            Effect: 'Allow',
            Principal: { Service: 'logging.s3.amazonaws.com' },
            Action: 's3:PutObject',
            Resource: `${bucketArn}/s3/*`,
            Condition: {
              StringEquals: { 's3:x-amz-acl': 'bucket-owner-full-control' },
            },
          },
          {
            Sid: 'AllowS3LogDeliveryAclCheck',
            Effect: 'Allow',
            Principal: { Service: 'logging.s3.amazonaws.com' },
            Action: 's3:GetBucketAcl',
            Resource: bucketArn,
          },
          {
            Sid: 'DenyInsecureTransport',
            Effect: 'Deny',
            Principal: '*',
            Action: 's3:*',
            Resource: [bucketArn, `${bucketArn}/*`],
            Condition: {
              Bool: { 'aws:SecureTransport': 'false' },
            },
          },
        ],
      },
    });

    // --------------------------------------------------------------------------------
    // Read shared SSM Parameters
    // --------------------------------------------------------------------------------

    const transitGatewayId = ssm.StringParameter.valueForStringParameter(
      this,
      sharedSsmParameterName(config.environment, 'transit-gateway-id'),
    );

    const endpointPhzZoneIdsJson = ssm.StringParameter.valueForStringParameter(
      this,
      sharedSsmParameterName(config.environment, 'endpoint-phz-zone-ids'),
    );

    // Parse endpoint PHZ zone IDs - these are resolved at deploy time via {{resolve:ssm:...}}
    // We need to pass the raw SSM value since it cannot be parsed at synth time
    // Instead, we pass individual zone IDs from config or use Fn.select on a known structure

    // --------------------------------------------------------------------------------
    // ProjectVpc Construct
    // --------------------------------------------------------------------------------

    const projectVpc = new ProjectVpc(this, 'ProjectVpc', {
      projectName: config.projectName,
      environment: config.environment,
      vpcCidr: config.vpcCidr,
      azs: config.azs,
      privateSubnets: config.privateSubnets,
      transitGatewayId,
      endpointPhzZoneIds: {},  // PHZ associations require zone IDs known at synth time; handled via CfnParameter or direct SSM lookup at deploy
      logsKmsKey: kmsKeys['logs'],
    });

    // --------------------------------------------------------------------------------
    // SecurityGroupSet Construct
    // --------------------------------------------------------------------------------

    const sgNames = [
      'ecs',
      'db',
      ...Object.keys(config.lanes).map((lane) => `${lane}-alb`),
    ];

    const sgSet = new SecurityGroupSet(this, 'SecurityGroupSet', {
      vpcId: projectVpc.vpc.ref,
      securityGroupNames: sgNames,
      namePrefix: prefix,
    });

    // --------------------------------------------------------------------------------
    // HostedZone Construct
    // --------------------------------------------------------------------------------

    const hostedZone = new HostedZone(this, 'HostedZone', {
      projectName: config.projectName,
      environment: config.environment,
      domainName: config.domainName,
      deployMode: config.deployMode,
    });

    // --------------------------------------------------------------------------------
    // DnsFirewall Construct (conditional)
    // --------------------------------------------------------------------------------

    if (config.enableDnsFirewall) {
      new DnsFirewall(this, 'DnsFirewall', {
        namePrefix: prefix,
        vpcId: projectVpc.vpc.ref,
      });
    }

    // --------------------------------------------------------------------------------
    // SSM Parameters
    // --------------------------------------------------------------------------------

    putSsmParameter(
      this, 'SsmVpcId',
      config.projectName, config.environment,
      'vpc-id', projectVpc.vpc.ref,
      'Project VPC ID',
    );

    const subnetRefs = Object.values(projectVpc.privateSubnetResources).map((s) => s.ref);

    putSsmParameter(
      this, 'SsmPrivateSubnetIds',
      config.projectName, config.environment,
      'private-subnet-ids',
      Fn.join(',', Object.values(projectVpc.privateSubnetResources).map((s) => s.ref)),
      'Project VPC private subnet IDs (comma-separated)',
    );

    for (const [name, sg] of Object.entries(sgSet.securityGroups)) {
      const cfnKey = toPascalCase(name);
      putSsmParameter(
        this, `SsmSg${cfnKey}`,
        config.projectName, config.environment,
        `sg/${name}/id`, sg.attrGroupId,
        `Security Group ID for ${name}`,
      );
    }

    for (const [keyName, key] of Object.entries(kmsKeys)) {
      const cfnKey = capitalize(keyName);
      putSsmParameter(
        this, `SsmKms${cfnKey}`,
        config.projectName, config.environment,
        `kms/${keyName}/arn`, key.keyArn,
        `KMS Key ARN for ${keyName}`,
      );
    }

    putSsmParameter(
      this, 'SsmAcmRegionalCertArn',
      config.projectName, config.environment,
      'acm/regional-cert-arn', hostedZone.regionalCertificate.ref,
      'ACM Regional Certificate ARN',
    );

    putSsmParameter(
      this, 'SsmHostedZoneId',
      config.projectName, config.environment,
      'hosted-zone-id', hostedZone.zone.ref,
      'Route53 Hosted Zone ID',
    );

    putSsmParameter(
      this, 'SsmLoggingBucketId',
      config.projectName, config.environment,
      'logging-bucket-id', loggingBucket.ref,
      'Logging S3 Bucket ID',
    );

    putSsmParameter(
      this, 'SsmLoggingBucketDomain',
      config.projectName, config.environment,
      'logging-bucket-domain', loggingBucket.attrDomainName,
      'Logging S3 Bucket Domain Name',
    );
  }
}

// --------------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------------

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function toPascalCase(s: string): string {
  return s
    .split('-')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}
