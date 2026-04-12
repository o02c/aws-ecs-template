import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { CfnResource } from 'aws-cdk-lib';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { RemovalPolicy } from 'aws-cdk-lib';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface ProjectVpcProps {
  projectName: string;
  environment: string;
  vpcCidr: string;
  azs: string[];
  privateSubnets: Record<string, string>;
  transitGatewayId: string;
  endpointPhzZoneIds: Record<string, string>;
  logsKmsKey: kms.IKey;
}

export class ProjectVpc extends Construct {
  public readonly vpc: ec2.CfnVPC;
  public readonly privateSubnetResources: Record<string, ec2.CfnSubnet>;

  constructor(scope: Construct, id: string, props: ProjectVpcProps) {
    super(scope, id);

    const prefix = `${props.projectName}-${props.environment}`;
    const region = regionFromAz(props.azs[0]);

    // --------------------------------------------------------------------------------
    // VPC
    // --------------------------------------------------------------------------------

    this.vpc = new ec2.CfnVPC(this, 'Vpc', {
      cidrBlock: props.vpcCidr,
      enableDnsSupport: true,
      enableDnsHostnames: true,
      tags: [{ key: 'Name', value: `${prefix}-vpc` }],
    });

    // --------------------------------------------------------------------------------
    // Internet Gateway (CloudFront VPC Origins requirement - logical marker)
    // --------------------------------------------------------------------------------

    const igw = new ec2.CfnInternetGateway(this, 'Igw', {
      tags: [{ key: 'Name', value: `${prefix}-igw` }],
    });

    new ec2.CfnVPCGatewayAttachment(this, 'IgwAttachment', {
      vpcId: this.vpc.ref,
      internetGatewayId: igw.ref,
    });

    // --------------------------------------------------------------------------------
    // Private Subnets
    // --------------------------------------------------------------------------------

    this.privateSubnetResources = {};
    for (const [az, cidr] of Object.entries(props.privateSubnets)) {
      const azSuffix = az.slice(-1);
      this.privateSubnetResources[az] = new ec2.CfnSubnet(this, `PrivateSubnet${azSuffix.toUpperCase()}`, {
        vpcId: this.vpc.ref,
        cidrBlock: cidr,
        availabilityZone: az,
        tags: [{ key: 'Name', value: `${prefix}-private-${az}` }],
      });
    }

    // --------------------------------------------------------------------------------
    // Private Route Table
    // --------------------------------------------------------------------------------

    const privateRt = new ec2.CfnRouteTable(this, 'PrivateRt', {
      vpcId: this.vpc.ref,
      tags: [{ key: 'Name', value: `${prefix}-private-rt` }],
    });

    for (const [az, subnet] of Object.entries(this.privateSubnetResources)) {
      const azSuffix = az.slice(-1);
      new ec2.CfnSubnetRouteTableAssociation(this, `PrivateRtAssoc${azSuffix.toUpperCase()}`, {
        subnetId: subnet.ref,
        routeTableId: privateRt.ref,
      });
    }

    // --------------------------------------------------------------------------------
    // Transit Gateway VPC Attachment
    // --------------------------------------------------------------------------------

    const tgwAttachment = new ec2.CfnTransitGatewayAttachment(this, 'TgwAttachment', {
      transitGatewayId: props.transitGatewayId,
      vpcId: this.vpc.ref,
      subnetIds: Object.values(this.privateSubnetResources).map((s) => s.ref),
      tags: [{ key: 'Name', value: `${prefix}-tgw-attach` }],
    });

    // --------------------------------------------------------------------------------
    // Default Route (0.0.0.0/0 -> TGW)
    // --------------------------------------------------------------------------------

    const defaultRoute = new ec2.CfnRoute(this, 'TgwDefaultRoute', {
      routeTableId: privateRt.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: props.transitGatewayId,
    });
    defaultRoute.addDependency(tgwAttachment);

    // --------------------------------------------------------------------------------
    // S3 Gateway Endpoint
    // --------------------------------------------------------------------------------

    new ec2.CfnVPCEndpoint(this, 'S3GatewayEndpoint', {
      vpcId: this.vpc.ref,
      serviceName: `com.amazonaws.${region}.s3`,
      vpcEndpointType: 'Gateway',
      routeTableIds: [privateRt.ref],
    });

    // --------------------------------------------------------------------------------
    // Route53 PHZ Association (shared VPC endpoint PHZs -> project VPC)
    // --------------------------------------------------------------------------------

    for (const [key, zoneId] of Object.entries(props.endpointPhzZoneIds)) {
      const cfnKey = toPascalCase(key);
      new CfnResource(this, `PhzAssoc${cfnKey}`, {
        type: 'AWS::Route53::HostedZoneVPCAssociation',
        properties: {
          HostedZoneId: zoneId,
          VPCId: this.vpc.ref,
          VPCRegion: region,
        },
      });
    }

    // --------------------------------------------------------------------------------
    // VPC Flow Logs (CloudWatch Logs, KMS encrypted)
    // --------------------------------------------------------------------------------

    const flowLogGroup = new logs.CfnLogGroup(this, 'FlowLogGroup', {
      logGroupName: `/aws/vpc/flow-log/${prefix}`,
      retentionInDays: 30,
      kmsKeyId: props.logsKmsKey.keyArn,
    });
    flowLogGroup.applyRemovalPolicy(RemovalPolicy.RETAIN);

    const flowLogRole = new iam.Role(this, 'FlowLogRole', {
      roleName: `${prefix}-flow-log`,
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
      tags: [{ key: 'Name', value: `${prefix}-flow-log` }],
    });
  }
}

// --------------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------------

function regionFromAz(az: string): string {
  return az.replace(/[a-z]$/, '');
}

function toPascalCase(s: string): string {
  return s
    .split('-')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}
