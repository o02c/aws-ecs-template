import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { LaneStack } from '../../lib/stacks/lane-stack';
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

describe('LaneStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new LaneStack(app, 'TestLaneStack', {
      config: testConfig,
      lane: 'user',
      env: { account: testConfig.account.accountId, region: testConfig.account.region },
    });
    template = Template.fromStack(stack);
  });

  // --------------------------------------------------------------------------------
  // Internal ALB
  // --------------------------------------------------------------------------------

  test('creates Internal Application Load Balancer', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::LoadBalancer', {
      Name: 'myapp-dev-user',
      Scheme: 'internal',
      Type: 'application',
    });
  });

  test('creates Target Group with health check', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::TargetGroup', {
      Name: 'myapp-dev-user',
      Port: 80,
      Protocol: 'HTTP',
      TargetType: 'ip',
      HealthCheckPath: '/health',
    });
  });

  test('creates HTTPS Listener with TLS 1.3 policy', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::Listener', {
      Port: 443,
      Protocol: 'HTTPS',
      SslPolicy: 'ELBSecurityPolicy-TLS13-1-2-2021-06',
    });
  });

  test('creates ALB egress SG rule to ECS on port 80', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroupEgress', {
      IpProtocol: 'tcp',
      FromPort: 80,
      ToPort: 80,
      Description: 'To ECS tasks',
    });
  });

  // --------------------------------------------------------------------------------
  // S3 Asset Bucket
  // --------------------------------------------------------------------------------

  test('creates S3 asset bucket with KMS encryption', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: 'myapp-dev-user-assets-123456789012',
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

  test('creates S3 bucket with public access block', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
  });

  test('creates CloudFront Origin Access Control', () => {
    template.hasResourceProperties('AWS::CloudFront::OriginAccessControl', {
      OriginAccessControlConfig: {
        Name: 'myapp-dev-user',
        OriginAccessControlOriginType: 's3',
        SigningBehavior: 'always',
        SigningProtocol: 'sigv4',
      },
    });
  });

  test('creates IAM policy for S3 access', () => {
    template.hasResourceProperties('AWS::IAM::ManagedPolicy', {
      ManagedPolicyName: 'myapp-dev-user-s3-access',
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: ['s3:GetObject', 's3:PutObject'],
          }),
        ]),
      }),
    });
  });

  // --------------------------------------------------------------------------------
  // CloudFront Distribution
  // --------------------------------------------------------------------------------

  test('creates CloudFront Distribution', () => {
    template.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        Enabled: true,
        IPV6Enabled: true,
        PriceClass: 'PriceClass_200',
        Comment: 'myapp-dev-user',
        Aliases: ['user.example.com'],
      }),
    });
  });

  test('creates CloudFront VPC Origin', () => {
    template.hasResourceProperties('AWS::CloudFront::VpcOrigin', {
      VpcOriginEndpointConfig: Match.objectLike({
        Name: 'myapp-dev-user-alb',
        OriginProtocolPolicy: 'https-only',
      }),
    });
  });

  test('CloudFront distribution has ALB and S3 origins', () => {
    template.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        Origins: Match.arrayWith([
          Match.objectLike({ Id: 'alb' }),
          Match.objectLike({ Id: 's3' }),
        ]),
      }),
    });
  });

  test('CloudFront distribution has /assets/* cache behavior for S3', () => {
    template.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        CacheBehaviors: Match.arrayWith([
          Match.objectLike({
            PathPattern: '/assets/*',
            TargetOriginId: 's3',
            ViewerProtocolPolicy: 'redirect-to-https',
          }),
        ]),
      }),
    });
  });

  test('CloudFront distribution has geo restriction for Japan', () => {
    template.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        Restrictions: {
          GeoRestriction: {
            RestrictionType: 'whitelist',
            Locations: ['JP'],
          },
        },
      }),
    });
  });

  test('creates CloudFront cache policy for static assets', () => {
    template.hasResourceProperties('AWS::CloudFront::CachePolicy', {
      CachePolicyConfig: Match.objectLike({
        Name: 'myapp-dev-user-static',
        DefaultTTL: 86400,
        MaxTTL: 31536000,
      }),
    });
  });

  // --------------------------------------------------------------------------------
  // Route53
  // --------------------------------------------------------------------------------

  test('creates Route53 A record for lane subdomain', () => {
    template.hasResourceProperties('AWS::Route53::RecordSet', {
      Name: 'user.example.com',
      Type: 'A',
      AliasTarget: Match.objectLike({
        HostedZoneId: 'Z2FDTNDATAQYW2',
      }),
    });
  });

  // --------------------------------------------------------------------------------
  // S3 Bucket Policy (CloudFront OAC)
  // --------------------------------------------------------------------------------

  test('creates S3 bucket policy for CloudFront OAC access', () => {
    template.hasResourceProperties('AWS::S3::BucketPolicy', {
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Sid: 'AllowCloudFrontServicePrincipal',
            Effect: 'Allow',
            Principal: { Service: 'cloudfront.amazonaws.com' },
            Action: 's3:GetObject',
          }),
        ]),
      }),
    });
  });

  // --------------------------------------------------------------------------------
  // SSM Parameters
  // --------------------------------------------------------------------------------

  test('creates SSM Parameters for target group and ALB DNS', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/target-group/user/arn',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/alb/user/dns-name',
    });
  });
});
