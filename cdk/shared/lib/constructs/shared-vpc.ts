import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Fn, RemovalPolicy } from 'aws-cdk-lib';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface SharedVpcProps {
  environment: string;
  vpcCidr: string;
  azs: string[];
  publicSubnets: Record<string, string>;
  privateSubnets: Record<string, string>;
  interfaceEndpoints: Record<string, string>;
  projectVpcCidrs: Record<string, string>;
  logsKmsKey: kms.IKey;
}

// --------------------------------------------------------------------------------
// Service domain mapping (endpoint key -> DNS prefix)
// --------------------------------------------------------------------------------

const ENDPOINT_DNS_PREFIX: Record<string, string> = {
  'ecr.api': 'api.ecr',
  'ecr.dkr': 'dkr.ecr',
  'logs': 'logs',
  'kinesis-firehose': 'firehose',
  'sts': 'sts',
  'ssm': 'ssm',
  'secretsmanager': 'secretsmanager',
};

export class SharedVpc extends Construct {
  public readonly vpc: ec2.CfnVPC;
  public readonly transitGateway: ec2.CfnTransitGateway;
  public readonly endpointPhzZoneIds: Record<string, string>;

  constructor(scope: Construct, id: string, props: SharedVpcProps) {
    super(scope, id);

    const prefix = `Shared-${props.environment}`;

    // --------------------------------------------------------------------------------
    // VPC
    // --------------------------------------------------------------------------------

    this.vpc = new ec2.CfnVPC(this, 'Vpc', {
      cidrBlock: props.vpcCidr,
      enableDnsSupport: true,
      enableDnsHostnames: true,
      tags: [{ key: 'Name', value: `${prefix}-shared-vpc` }],
    });

    // --------------------------------------------------------------------------------
    // Internet Gateway
    // --------------------------------------------------------------------------------

    const igw = new ec2.CfnInternetGateway(this, 'Igw', {
      tags: [{ key: 'Name', value: `${prefix}-shared-igw` }],
    });

    new ec2.CfnVPCGatewayAttachment(this, 'IgwAttachment', {
      vpcId: this.vpc.ref,
      internetGatewayId: igw.ref,
    });

    // --------------------------------------------------------------------------------
    // Public Subnets
    // --------------------------------------------------------------------------------

    const publicSubnetResources: Record<string, ec2.CfnSubnet> = {};
    for (const [az, cidr] of Object.entries(props.publicSubnets)) {
      const azSuffix = az.slice(-1);
      publicSubnetResources[az] = new ec2.CfnSubnet(this, `PublicSubnet${azSuffix.toUpperCase()}`, {
        vpcId: this.vpc.ref,
        cidrBlock: cidr,
        availabilityZone: az,
        tags: [{ key: 'Name', value: `${prefix}-shared-public-${az}` }],
      });
    }

    // --------------------------------------------------------------------------------
    // Public Route Table
    // --------------------------------------------------------------------------------

    const publicRt = new ec2.CfnRouteTable(this, 'PublicRt', {
      vpcId: this.vpc.ref,
      tags: [{ key: 'Name', value: `${prefix}-shared-public-rt` }],
    });

    new ec2.CfnRoute(this, 'PublicDefaultRoute', {
      routeTableId: publicRt.ref,
      destinationCidrBlock: '0.0.0.0/0',
      gatewayId: igw.ref,
    });

    for (const [az, subnet] of Object.entries(publicSubnetResources)) {
      const azSuffix = az.slice(-1);
      new ec2.CfnSubnetRouteTableAssociation(this, `PublicRtAssoc${azSuffix.toUpperCase()}`, {
        subnetId: subnet.ref,
        routeTableId: publicRt.ref,
      });
    }

    // --------------------------------------------------------------------------------
    // NAT Gateway (single, cost reduction - AZ-a only)
    // --------------------------------------------------------------------------------

    const firstAz = props.azs[0];

    const eip = new ec2.CfnEIP(this, 'NatEip', {
      domain: 'vpc',
      tags: [{ key: 'Name', value: `${prefix}-shared-nat-eip` }],
    });

    const natGw = new ec2.CfnNatGateway(this, 'NatGw', {
      subnetId: publicSubnetResources[firstAz].ref,
      allocationId: eip.attrAllocationId,
      tags: [{ key: 'Name', value: `${prefix}-shared-nat` }],
    });

    // --------------------------------------------------------------------------------
    // Private Subnets
    // --------------------------------------------------------------------------------

    const privateSubnetResources: Record<string, ec2.CfnSubnet> = {};
    for (const [az, cidr] of Object.entries(props.privateSubnets)) {
      const azSuffix = az.slice(-1);
      privateSubnetResources[az] = new ec2.CfnSubnet(this, `PrivateSubnet${azSuffix.toUpperCase()}`, {
        vpcId: this.vpc.ref,
        cidrBlock: cidr,
        availabilityZone: az,
        tags: [{ key: 'Name', value: `${prefix}-shared-private-${az}` }],
      });
    }

    // --------------------------------------------------------------------------------
    // Private Route Tables (per AZ)
    // --------------------------------------------------------------------------------

    const privateRts: Record<string, ec2.CfnRouteTable> = {};
    for (const az of Object.keys(props.privateSubnets)) {
      const azSuffix = az.slice(-1);
      const rt = new ec2.CfnRouteTable(this, `PrivateRt${azSuffix.toUpperCase()}`, {
        vpcId: this.vpc.ref,
        tags: [{ key: 'Name', value: `${prefix}-shared-private-rt-${az}` }],
      });
      privateRts[az] = rt;

      new ec2.CfnRoute(this, `PrivateNatRoute${azSuffix.toUpperCase()}`, {
        routeTableId: rt.ref,
        destinationCidrBlock: '0.0.0.0/0',
        natGatewayId: natGw.ref,
      });

      new ec2.CfnSubnetRouteTableAssociation(this, `PrivateRtAssoc${azSuffix.toUpperCase()}`, {
        subnetId: privateSubnetResources[az].ref,
        routeTableId: rt.ref,
      });
    }

    // --------------------------------------------------------------------------------
    // Transit Gateway
    // --------------------------------------------------------------------------------

    this.transitGateway = new ec2.CfnTransitGateway(this, 'Tgw', {
      description: `${prefix}-tgw`,
      defaultRouteTableAssociation: 'disable',
      defaultRouteTablePropagation: 'disable',
      dnsSupport: 'enable',
      tags: [{ key: 'Name', value: `${prefix}-tgw` }],
    });

    // --------------------------------------------------------------------------------
    // Transit Gateway Route Table
    // --------------------------------------------------------------------------------

    const tgwRouteTable = new ec2.CfnTransitGatewayRouteTable(this, 'TgwRouteTable', {
      transitGatewayId: this.transitGateway.ref,
      tags: [{ key: 'Name', value: `${prefix}-tgw-rt` }],
    });

    // --------------------------------------------------------------------------------
    // Transit Gateway VPC Attachment (shared VPC)
    // --------------------------------------------------------------------------------

    const tgwAttachment = new ec2.CfnTransitGatewayAttachment(this, 'TgwAttachment', {
      transitGatewayId: this.transitGateway.ref,
      vpcId: this.vpc.ref,
      subnetIds: Object.values(privateSubnetResources).map((s) => s.ref),
      tags: [{ key: 'Name', value: `${prefix}-shared-tgw-attach` }],
    });

    // Associate attachment with route table
    new ec2.CfnTransitGatewayRouteTableAssociation(this, 'TgwRtAssocShared', {
      transitGatewayAttachmentId: tgwAttachment.ref,
      transitGatewayRouteTableId: tgwRouteTable.ref,
    });

    // Propagate routes from attachment to route table
    new ec2.CfnTransitGatewayRouteTablePropagation(this, 'TgwRtPropShared', {
      transitGatewayAttachmentId: tgwAttachment.ref,
      transitGatewayRouteTableId: tgwRouteTable.ref,
    });

    // --------------------------------------------------------------------------------
    // Transit Gateway Route (default route to shared VPC)
    // --------------------------------------------------------------------------------

    new ec2.CfnTransitGatewayRoute(this, 'TgwDefaultRoute', {
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayAttachmentId: tgwAttachment.ref,
      transitGatewayRouteTableId: tgwRouteTable.ref,
    });

    // --------------------------------------------------------------------------------
    // Public Route Table: routes to project VPCs via TGW
    // --------------------------------------------------------------------------------

    for (const [project, cidr] of Object.entries(props.projectVpcCidrs)) {
      const route = new ec2.CfnRoute(this, `PublicToProject${capitalize(project)}`, {
        routeTableId: publicRt.ref,
        destinationCidrBlock: cidr,
        transitGatewayId: this.transitGateway.ref,
      });
      route.addDependency(tgwAttachment);
    }

    // --------------------------------------------------------------------------------
    // Private Route Tables: return routes to project VPCs via TGW
    // --------------------------------------------------------------------------------

    for (const [az, rt] of Object.entries(privateRts)) {
      const azSuffix = az.slice(-1);
      for (const [project, cidr] of Object.entries(props.projectVpcCidrs)) {
        const route = new ec2.CfnRoute(this, `PrivateToProject${azSuffix.toUpperCase()}${capitalize(project)}`, {
          routeTableId: rt.ref,
          destinationCidrBlock: cidr,
          transitGatewayId: this.transitGateway.ref,
        });
        route.addDependency(tgwAttachment);
      }
    }

    // --------------------------------------------------------------------------------
    // S3 Gateway Endpoint
    // --------------------------------------------------------------------------------

    new ec2.CfnVPCEndpoint(this, 'S3GatewayEndpoint', {
      vpcId: this.vpc.ref,
      serviceName: `com.amazonaws.${regionFromAz(firstAz)}.s3`,
      vpcEndpointType: 'Gateway',
      routeTableIds: Object.values(privateRts).map((rt) => rt.ref),
      policyDocument: vpcEndpointPolicy(this),
    });

    // --------------------------------------------------------------------------------
    // VPC Endpoint Security Group
    // --------------------------------------------------------------------------------

    const vpceSg = new ec2.CfnSecurityGroup(this, 'VpceSg', {
      groupDescription: 'Security group for shared VPC endpoints',
      vpcId: this.vpc.ref,
      securityGroupIngress: [
        {
          ipProtocol: 'tcp',
          fromPort: 443,
          toPort: 443,
          cidrIp: props.vpcCidr,
          description: 'HTTPS from shared VPC',
        },
        ...Object.entries(props.projectVpcCidrs).map(([project, cidr]) => ({
          ipProtocol: 'tcp',
          fromPort: 443,
          toPort: 443,
          cidrIp: cidr,
          description: `HTTPS from ${project} VPC`,
        })),
      ],
      tags: [{ key: 'Name', value: `${prefix}-shared-vpce` }],
    });

    // --------------------------------------------------------------------------------
    // Interface VPC Endpoints + Route53 Private Hosted Zones
    // --------------------------------------------------------------------------------

    const region = regionFromAz(firstAz);
    this.endpointPhzZoneIds = {};

    for (const [key, serviceSuffix] of Object.entries(props.interfaceEndpoints)) {
      const serviceName = `com.amazonaws.${region}.${serviceSuffix}`;
      const dnsPrefix = ENDPOINT_DNS_PREFIX[serviceSuffix] ?? serviceSuffix;
      const phzDomain = `${dnsPrefix}.${region}.amazonaws.com`;
      const cfnKey = toPascalCase(key);

      // Interface Endpoint
      const endpoint = new ec2.CfnVPCEndpoint(this, `Endpoint${cfnKey}`, {
        vpcId: this.vpc.ref,
        serviceName,
        vpcEndpointType: 'Interface',
        privateDnsEnabled: false,
        subnetIds: Object.values(privateSubnetResources).map((s) => s.ref),
        securityGroupIds: [vpceSg.attrGroupId],
        policyDocument: vpcEndpointPolicy(this),
      });

      // Route53 Private Hosted Zone
      const phz = new route53.CfnHostedZone(this, `Phz${cfnKey}`, {
        name: phzDomain,
        vpcs: [{ vpcId: this.vpc.ref, vpcRegion: region }],
        hostedZoneConfig: {
          comment: `PHZ for ${key} endpoint`,
        },
        hostedZoneTags: [{ key: 'Name', value: `${prefix}-shared-${key}-phz` }],
      });

      this.endpointPhzZoneIds[key] = phz.ref;

      // A record (ALIAS to endpoint)
      new route53.CfnRecordSet(this, `Record${cfnKey}`, {
        hostedZoneId: phz.ref,
        name: phzDomain,
        type: 'A',
        aliasTarget: {
          dnsName: Fn.select(1, Fn.split(':', Fn.select(0, endpoint.attrDnsEntries))),
          hostedZoneId: Fn.select(0, Fn.split(':', Fn.select(0, endpoint.attrDnsEntries))),
          evaluateTargetHealth: true,
        },
      });

      // ECR DKR needs wildcard record
      if (dnsPrefix === 'dkr.ecr') {
        new route53.CfnRecordSet(this, `RecordWildcard${cfnKey}`, {
          hostedZoneId: phz.ref,
          name: `*.${phzDomain}`,
          type: 'A',
          aliasTarget: {
            dnsName: Fn.select(1, Fn.split(':', Fn.select(0, endpoint.attrDnsEntries))),
            hostedZoneId: Fn.select(0, Fn.split(':', Fn.select(0, endpoint.attrDnsEntries))),
            evaluateTargetHealth: true,
          },
        });
      }
    }

    // --------------------------------------------------------------------------------
    // VPC Flow Logs (CloudWatch Logs, KMS encrypted)
    // --------------------------------------------------------------------------------

    const flowLogGroup = new logs.CfnLogGroup(this, 'FlowLogGroup', {
      logGroupName: `/aws/vpc/flow-log/${prefix}-shared`,
      retentionInDays: 30,
      kmsKeyId: props.logsKmsKey.keyArn,
    });
    flowLogGroup.applyRemovalPolicy(RemovalPolicy.RETAIN);

    const flowLogRole = new iam.Role(this, 'FlowLogRole', {
      roleName: `${prefix}-shared-flow-log`,
      assumedBy: new iam.ServicePrincipal('vpc-flow-logs.amazonaws.com'),
    });

    flowLogRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
          'logs:DescribeLogGroups',
          'logs:DescribeLogStreams',
        ],
        resources: [
          flowLogGroup.attrArn,
          `${flowLogGroup.attrArn}:*`,
        ],
      }),
    );

    new ec2.CfnFlowLog(this, 'FlowLog', {
      resourceId: this.vpc.ref,
      resourceType: 'VPC',
      trafficType: 'ALL',
      logDestinationType: 'cloud-watch-logs',
      logGroupName: flowLogGroup.logGroupName!,
      deliverLogsPermissionArn: flowLogRole.roleArn,
      tags: [{ key: 'Name', value: `${prefix}-shared-flow-log` }],
    });
  }
}

// --------------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------------

function regionFromAz(az: string): string {
  return az.replace(/[a-z]$/, '');
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function toPascalCase(s: string): string {
  return s
    .split('-')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}

function vpcEndpointPolicy(scope: Construct): Record<string, unknown> {
  const accountId = new iam.AccountRootPrincipal().accountId;
  return {
    Version: '2012-10-17',
    Statement: [
      {
        Sid: 'AllowAll',
        Effect: 'Allow',
        Principal: '*',
        Action: '*',
        Resource: '*',
      },
      {
        Sid: 'DenyOtherAwsAccountPrincipals',
        Effect: 'Deny',
        Principal: '*',
        Action: '*',
        Resource: '*',
        Condition: {
          StringNotEquals: {
            'aws:PrincipalAccount': accountId,
          },
        },
      },
    ],
  };
}
