import { Stack, StackProps } from 'aws-cdk-lib';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { SharedConfig } from '../helpers/config-types';
import { SharedVpc } from '../constructs/shared-vpc';
import { DnsFirewall } from '../constructs/dns-firewall';
import { putSsmParameter } from '../helpers/ssm';

export interface NetworkStackProps extends StackProps {
  config: SharedConfig;
}

export class NetworkStack extends Stack {
  constructor(scope: Construct, id: string, props: NetworkStackProps) {
    super(scope, id, props);

    const { config } = props;
    const prefix = `Shared-${config.environment}`;

    // --------------------------------------------------------------------------------
    // KMS Keys (direct, not a Construct)
    // --------------------------------------------------------------------------------

    const generalKey = new kms.Key(this, 'GeneralKey', {
      description: 'CMK for shared infrastructure encryption',
      enableKeyRotation: true,
      alias: `alias/${prefix}-shared-general`,
    });
    const cfnGeneralKey = generalKey.node.defaultChild as kms.CfnKey;
    cfnGeneralKey.pendingWindowInDays = 30;

    const logsKey = new kms.Key(this, 'LogsKey', {
      description: 'CMK for CloudWatch Logs encryption',
      enableKeyRotation: true,
      alias: `alias/${prefix}-shared-logs`,
    });
    const cfnLogsKey = logsKey.node.defaultChild as kms.CfnKey;
    cfnLogsKey.pendingWindowInDays = 30;

    // Allow CloudWatch Logs service to use the logs key
    logsKey.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudWatchLogs',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal(`logs.${config.account.region}.amazonaws.com`)],
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
            'kms:EncryptionContext:aws:logs:arn': `arn:aws:logs:${config.account.region}:${config.account.accountId}:log-group:*`,
          },
        },
      }),
    );

    // --------------------------------------------------------------------------------
    // SharedVpc Construct
    // --------------------------------------------------------------------------------

    const sharedVpc = new SharedVpc(this, 'SharedVpc', {
      environment: config.environment,
      vpcCidr: config.vpcCidr,
      azs: config.azs,
      publicSubnets: config.publicSubnets,
      privateSubnets: config.privateSubnets,
      interfaceEndpoints: config.interfaceEndpoints,
      projectVpcCidrs: config.projectVpcCidrs,
      logsKmsKey: logsKey,
    });

    // --------------------------------------------------------------------------------
    // DnsFirewall Construct
    // --------------------------------------------------------------------------------

    new DnsFirewall(this, 'DnsFirewall', {
      environment: config.environment,
      vpcId: sharedVpc.vpc.ref,
    });

    // --------------------------------------------------------------------------------
    // SSM Parameters
    // --------------------------------------------------------------------------------

    putSsmParameter(
      this,
      'SsmTgwId',
      config.environment,
      'transit-gateway-id',
      sharedVpc.transitGateway.ref,
      'Transit Gateway ID for project VPC attachments',
    );

    putSsmParameter(
      this,
      'SsmPrivateSubnetCidrs',
      config.environment,
      'private-subnet-cidrs',
      JSON.stringify(Object.values(config.privateSubnets)),
      'Shared VPC private subnet CIDRs',
    );

    putSsmParameter(
      this,
      'SsmEndpointPhzZoneIds',
      config.environment,
      'endpoint-phz-zone-ids',
      JSON.stringify(sharedVpc.endpointPhzZoneIds),
      'Map of endpoint identifier to Route53 PHZ zone ID',
    );

    putSsmParameter(
      this,
      'SsmVpcId',
      config.environment,
      'vpc-id',
      sharedVpc.vpc.ref,
      'Shared VPC ID',
    );
  }
}
