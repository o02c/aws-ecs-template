import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { FoundationStack } from '../../lib/stacks/foundation-stack';
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

describe('FoundationStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new FoundationStack(app, 'TestFoundationStack', {
      config: testConfig,
      env: { account: testConfig.account.accountId, region: testConfig.account.region },
    });
    template = Template.fromStack(stack);
  });

  // --------------------------------------------------------------------------------
  // KMS Keys
  // --------------------------------------------------------------------------------

  test('creates 4 KMS keys (rds, s3, logs, secrets)', () => {
    template.resourceCountIs('AWS::KMS::Key', 4);
  });

  test('creates KMS aliases for all keys', () => {
    template.hasResourceProperties('AWS::KMS::Alias', {
      AliasName: 'alias/myapp-dev-rds',
    });
    template.hasResourceProperties('AWS::KMS::Alias', {
      AliasName: 'alias/myapp-dev-s3',
    });
    template.hasResourceProperties('AWS::KMS::Alias', {
      AliasName: 'alias/myapp-dev-logs',
    });
    template.hasResourceProperties('AWS::KMS::Alias', {
      AliasName: 'alias/myapp-dev-secrets',
    });
  });

  // --------------------------------------------------------------------------------
  // Logging S3 Bucket
  // --------------------------------------------------------------------------------

  test('creates access log S3 bucket with AES256 encryption', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: 'myapp-dev-access-logs-123456789012',
      VersioningConfiguration: { Status: 'Enabled' },
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256',
            },
          },
        ],
      },
    });
  });

  test('creates bucket policy with log delivery and deny insecure transport', () => {
    template.hasResourceProperties('AWS::S3::BucketPolicy', {
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({ Sid: 'AllowCloudFrontLogDelivery' }),
          Match.objectLike({ Sid: 'AllowALBLogDelivery' }),
          Match.objectLike({ Sid: 'AllowS3LogDelivery' }),
          Match.objectLike({ Sid: 'DenyInsecureTransport' }),
        ]),
      }),
    });
  });

  test('S3 bucket has lifecycle rules (90d glacier, 365d expire)', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      LifecycleConfiguration: {
        Rules: [
          Match.objectLike({
            Status: 'Enabled',
            Transitions: [{ StorageClass: 'GLACIER', TransitionInDays: 90 }],
            ExpirationInDays: 365,
          }),
        ],
      },
    });
  });

  // --------------------------------------------------------------------------------
  // VPC
  // --------------------------------------------------------------------------------

  test('creates VPC with correct CIDR', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.1.0.0/16',
      EnableDnsSupport: true,
      EnableDnsHostnames: true,
    });
  });

  test('creates Internet Gateway (CloudFront VPC Origins marker)', () => {
    template.resourceCountIs('AWS::EC2::InternetGateway', 1);
  });

  test('creates private subnets per AZ', () => {
    template.resourceCountIs('AWS::EC2::Subnet', 2);
  });

  test('creates Transit Gateway VPC Attachment', () => {
    template.resourceCountIs('AWS::EC2::TransitGatewayAttachment', 1);
  });

  test('creates default route to TGW (0.0.0.0/0)', () => {
    template.hasResourceProperties('AWS::EC2::Route', {
      DestinationCidrBlock: '0.0.0.0/0',
    });
  });

  test('creates S3 Gateway Endpoint', () => {
    template.hasResourceProperties('AWS::EC2::VPCEndpoint', {
      ServiceName: 'com.amazonaws.ap-northeast-1.s3',
      VpcEndpointType: 'Gateway',
    });
  });

  // --------------------------------------------------------------------------------
  // VPC Flow Logs
  // --------------------------------------------------------------------------------

  test('creates VPC Flow Log', () => {
    template.hasResourceProperties('AWS::EC2::FlowLog', {
      ResourceType: 'VPC',
      TrafficType: 'ALL',
      LogDestinationType: 'cloud-watch-logs',
    });
  });

  test('creates CloudWatch Log Group for flow logs with KMS encryption', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/aws/vpc/flow-log/myapp-dev',
      RetentionInDays: 30,
    });
    const logGroups = template.findResources('AWS::Logs::LogGroup');
    const logGroup = Object.values(logGroups)[0];
    expect(logGroup.Properties.KmsKeyId).toBeDefined();
  });

  // --------------------------------------------------------------------------------
  // Security Groups
  // --------------------------------------------------------------------------------

  test('creates empty security groups (ecs, db, user-alb, admin-alb)', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for ecs',
    });
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for db',
    });
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for user-alb',
    });
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for admin-alb',
    });
  });

  // --------------------------------------------------------------------------------
  // Route53 / ACM
  // --------------------------------------------------------------------------------

  test('creates Route53 Public Hosted Zone', () => {
    template.hasResourceProperties('AWS::Route53::HostedZone', {
      Name: 'example.com',
    });
  });

  test('creates ACM Regional Certificate with DNS validation', () => {
    template.hasResourceProperties('AWS::CertificateManager::Certificate', {
      DomainName: 'example.com',
      ValidationMethod: 'DNS',
    });
  });

  // --------------------------------------------------------------------------------
  // DNS Firewall
  // --------------------------------------------------------------------------------

  test('creates DNS Firewall Domain List when enabled', () => {
    template.hasResourceProperties('AWS::Route53Resolver::FirewallDomainList', {
      Name: 'myapp-dev-block',
    });
  });

  test('creates DNS Firewall Rule Group', () => {
    template.hasResourceProperties('AWS::Route53Resolver::FirewallRuleGroup', {
      Name: 'myapp-dev',
    });
  });

  test('creates DNS Firewall Rule Group Association', () => {
    template.resourceCountIs('AWS::Route53Resolver::FirewallRuleGroupAssociation', 1);
  });

  // --------------------------------------------------------------------------------
  // SSM Parameters
  // --------------------------------------------------------------------------------

  test('creates SSM Parameters for cross-stack references', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/vpc-id',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/private-subnet-ids',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/sg/ecs/id',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/sg/db/id',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/sg/user-alb/id',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/sg/admin-alb/id',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/kms/rds/arn',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/kms/s3/arn',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/kms/logs/arn',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/kms/secrets/arn',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/acm/regional-cert-arn',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/logging-bucket-id',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/logging-bucket-domain',
    });
  });
});

describe('FoundationStack - DNS Firewall disabled', () => {
  test('does not create DNS Firewall resources when disabled', () => {
    const app = new cdk.App();
    const disabledConfig = { ...testConfig, enableDnsFirewall: false };
    const stack = new FoundationStack(app, 'TestFoundationStackNoFirewall', {
      config: disabledConfig,
      env: { account: testConfig.account.accountId, region: testConfig.account.region },
    });
    const tmpl = Template.fromStack(stack);
    tmpl.resourceCountIs('AWS::Route53Resolver::FirewallDomainList', 0);
    tmpl.resourceCountIs('AWS::Route53Resolver::FirewallRuleGroup', 0);
    tmpl.resourceCountIs('AWS::Route53Resolver::FirewallRuleGroupAssociation', 0);
  });
});
