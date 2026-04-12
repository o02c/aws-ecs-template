import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../../lib/stacks/network-stack';
import { SharedConfig } from '../../lib/helpers/config-types';

const testConfig: SharedConfig = {
  account: { accountId: '123456789012', region: 'ap-northeast-1' },
  environment: 'dev',
  vpcCidr: '10.0.0.0/16',
  azs: ['ap-northeast-1a', 'ap-northeast-1c'],
  publicSubnets: {
    'ap-northeast-1a': '10.0.1.0/24',
    'ap-northeast-1c': '10.0.2.0/24',
  },
  privateSubnets: {
    'ap-northeast-1a': '10.0.11.0/24',
    'ap-northeast-1c': '10.0.12.0/24',
  },
  interfaceEndpoints: {
    'ecr-api': 'ecr.api',
    'ecr-dkr': 'ecr.dkr',
    'logs': 'logs',
    'firehose': 'kinesis-firehose',
    'sts': 'sts',
    'ssm': 'ssm',
    'secretsmanager': 'secretsmanager',
  },
  projectVpcCidrs: {
    myapp: '10.1.0.0/16',
  },
};

describe('NetworkStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new NetworkStack(app, 'TestNetworkStack', {
      config: testConfig,
      env: { account: testConfig.account.accountId, region: testConfig.account.region },
    });
    template = Template.fromStack(stack);
  });

  // --------------------------------------------------------------------------------
  // VPC
  // --------------------------------------------------------------------------------

  test('creates VPC with correct CIDR', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.0.0.0/16',
      EnableDnsSupport: true,
      EnableDnsHostnames: true,
    });
  });

  // --------------------------------------------------------------------------------
  // Subnets
  // --------------------------------------------------------------------------------

  test('creates public subnets', () => {
    template.resourceCountIs('AWS::EC2::Subnet', 4);
  });

  // --------------------------------------------------------------------------------
  // NAT Gateway
  // --------------------------------------------------------------------------------

  test('creates single NAT Gateway', () => {
    template.resourceCountIs('AWS::EC2::NatGateway', 1);
  });

  test('creates EIP for NAT Gateway', () => {
    template.resourceCountIs('AWS::EC2::EIP', 1);
  });

  // --------------------------------------------------------------------------------
  // Internet Gateway
  // --------------------------------------------------------------------------------

  test('creates Internet Gateway', () => {
    template.resourceCountIs('AWS::EC2::InternetGateway', 1);
  });

  // --------------------------------------------------------------------------------
  // Transit Gateway
  // --------------------------------------------------------------------------------

  test('creates Transit Gateway', () => {
    template.hasResourceProperties('AWS::EC2::TransitGateway', {
      DefaultRouteTableAssociation: 'disable',
      DefaultRouteTablePropagation: 'disable',
      DnsSupport: 'enable',
    });
  });

  test('creates Transit Gateway Route Table', () => {
    template.resourceCountIs('AWS::EC2::TransitGatewayRouteTable', 1);
  });

  test('creates Transit Gateway VPC Attachment', () => {
    template.resourceCountIs('AWS::EC2::TransitGatewayAttachment', 1);
  });

  test('creates Transit Gateway default route', () => {
    template.hasResourceProperties('AWS::EC2::TransitGatewayRoute', {
      DestinationCidrBlock: '0.0.0.0/0',
    });
  });

  // --------------------------------------------------------------------------------
  // VPC Endpoints
  // --------------------------------------------------------------------------------

  test('creates S3 Gateway Endpoint', () => {
    template.hasResourceProperties('AWS::EC2::VPCEndpoint', {
      ServiceName: 'com.amazonaws.ap-northeast-1.s3',
      VpcEndpointType: 'Gateway',
    });
  });

  test('creates 7 Interface Endpoints', () => {
    const endpoints = template.findResources('AWS::EC2::VPCEndpoint', {
      Properties: {
        VpcEndpointType: 'Interface',
      },
    });
    expect(Object.keys(endpoints)).toHaveLength(7);
  });

  test('Interface Endpoints have private DNS disabled', () => {
    const endpoints = template.findResources('AWS::EC2::VPCEndpoint', {
      Properties: {
        VpcEndpointType: 'Interface',
      },
    });
    for (const key of Object.keys(endpoints)) {
      expect(endpoints[key].Properties.PrivateDnsEnabled).toBe(false);
    }
  });

  // --------------------------------------------------------------------------------
  // VPC Endpoint Security Group
  // --------------------------------------------------------------------------------

  test('creates VPC Endpoint Security Group with HTTPS ingress', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for shared VPC endpoints',
      SecurityGroupIngress: [
        {
          IpProtocol: 'tcp',
          FromPort: 443,
          ToPort: 443,
          CidrIp: '10.0.0.0/16',
          Description: 'HTTPS from shared VPC',
        },
        {
          IpProtocol: 'tcp',
          FromPort: 443,
          ToPort: 443,
          CidrIp: '10.1.0.0/16',
          Description: 'HTTPS from myapp VPC',
        },
      ],
    });
  });

  // --------------------------------------------------------------------------------
  // Route53 Private Hosted Zones
  // --------------------------------------------------------------------------------

  test('creates Route53 PHZ for each interface endpoint', () => {
    template.resourceCountIs('AWS::Route53::HostedZone', 7);
  });

  test('creates A records for endpoints', () => {
    const records = template.findResources('AWS::Route53::RecordSet', {
      Properties: {
        Type: 'A',
      },
    });
    // 7 endpoints + 1 wildcard for ecr-dkr = 8
    expect(Object.keys(records)).toHaveLength(8);
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
      LogGroupName: '/aws/vpc/flow-log/Shared-dev-shared',
      RetentionInDays: 30,
    });
    // Verify KMS key is set (any key reference)
    const logGroups = template.findResources('AWS::Logs::LogGroup');
    const logGroup = Object.values(logGroups)[0];
    expect(logGroup.Properties.KmsKeyId).toBeDefined();
  });

  // --------------------------------------------------------------------------------
  // KMS Keys
  // --------------------------------------------------------------------------------

  test('creates 2 KMS keys (general + logs)', () => {
    template.resourceCountIs('AWS::KMS::Key', 2);
  });

  test('creates KMS aliases', () => {
    template.hasResourceProperties('AWS::KMS::Alias', {
      AliasName: 'alias/Shared-dev-shared-general',
    });
    template.hasResourceProperties('AWS::KMS::Alias', {
      AliasName: 'alias/Shared-dev-shared-logs',
    });
  });

  // --------------------------------------------------------------------------------
  // DNS Firewall
  // --------------------------------------------------------------------------------

  test('creates DNS Firewall Domain List', () => {
    template.hasResourceProperties('AWS::Route53Resolver::FirewallDomainList', {
      Name: 'Shared-dev-block',
    });
  });

  test('creates DNS Firewall Rule Group', () => {
    template.hasResourceProperties('AWS::Route53Resolver::FirewallRuleGroup', {
      Name: 'Shared-dev',
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
      Name: '/shared/dev/infra/transit-gateway-id',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/shared/dev/infra/private-subnet-cidrs',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/shared/dev/infra/endpoint-phz-zone-ids',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/shared/dev/infra/vpc-id',
    });
  });
});
