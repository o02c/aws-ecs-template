import { Construct } from 'constructs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface InternalAlbProps {
  namePrefix: string;
  lane: string;
  vpcId: string;
  privateSubnetIds: string[];
  albSecurityGroupId: string;
  ecsSecurityGroupId: string;
  acmCertificateArn: string;
  logBucketId: string;
  containerPort?: number;
}

export class InternalAlb extends Construct {
  public readonly alb: elbv2.CfnLoadBalancer;
  public readonly targetGroup: elbv2.CfnTargetGroup;
  public readonly listener: elbv2.CfnListener;

  constructor(scope: Construct, id: string, props: InternalAlbProps) {
    super(scope, id);

    const containerPort = props.containerPort ?? 80;
    const name = `${props.namePrefix}-${props.lane}`;

    // --------------------------------------------------------------------------------
    // Internal Application Load Balancer
    // --------------------------------------------------------------------------------

    this.alb = new elbv2.CfnLoadBalancer(this, 'Alb', {
      name,
      scheme: 'internal',
      type: 'application',
      securityGroups: [props.albSecurityGroupId],
      subnets: props.privateSubnetIds,
      loadBalancerAttributes: [
        { key: 'access_logs.s3.enabled', value: 'true' },
        { key: 'access_logs.s3.bucket', value: props.logBucketId },
        { key: 'access_logs.s3.prefix', value: `alb/${props.lane}` },
      ],
      tags: [{ key: 'Name', value: name }],
    });

    // --------------------------------------------------------------------------------
    // Target Group
    // --------------------------------------------------------------------------------

    this.targetGroup = new elbv2.CfnTargetGroup(this, 'TargetGroup', {
      name,
      port: 80,
      protocol: 'HTTP',
      vpcId: props.vpcId,
      targetType: 'ip',
      targetGroupAttributes: [
        { key: 'deregistration_delay.timeout_seconds', value: '30' },
      ],
      healthCheckPath: '/health',
      healthyThresholdCount: 2,
      unhealthyThresholdCount: 3,
      healthCheckTimeoutSeconds: 5,
      healthCheckIntervalSeconds: 30,
      matcher: { httpCode: '200' },
      tags: [{ key: 'Name', value: name }],
    });

    // --------------------------------------------------------------------------------
    // HTTPS Listener
    // --------------------------------------------------------------------------------

    this.listener = new elbv2.CfnListener(this, 'HttpsListener', {
      loadBalancerArn: this.alb.ref,
      port: 443,
      protocol: 'HTTPS',
      sslPolicy: 'ELBSecurityPolicy-TLS13-1-2-2021-06',
      certificates: [{ certificateArn: props.acmCertificateArn }],
      defaultActions: [
        {
          type: 'forward',
          targetGroupArn: this.targetGroup.ref,
        },
      ],
    });

    // --------------------------------------------------------------------------------
    // Security Group Rule: ALB egress to ECS on container port
    // --------------------------------------------------------------------------------

    new ec2.CfnSecurityGroupEgress(this, 'AlbToEcs', {
      groupId: props.albSecurityGroupId,
      ipProtocol: 'tcp',
      fromPort: containerPort,
      toPort: containerPort,
      destinationSecurityGroupId: props.ecsSecurityGroupId,
      description: 'To ECS tasks',
    });
  }
}
