import { Stack, StackProps, Fn } from 'aws-cdk-lib';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';
import { ProjectConfig } from '../helpers/config-types';
import { InternalAlb } from '../constructs/internal-alb';
import { AssetBucket } from '../constructs/asset-bucket';
import { LaneDistribution } from '../constructs/lane-distribution';
import { putSsmParameter, ssmParameterName } from '../helpers/ssm';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface LaneStackProps extends StackProps {
  config: ProjectConfig;
  lane: string;
}

export class LaneStack extends Stack {
  constructor(scope: Construct, id: string, props: LaneStackProps) {
    super(scope, id, props);

    const { config, lane } = props;
    const prefix = `${config.projectName}-${config.environment}`;
    const accountId = config.account.accountId;

    // --------------------------------------------------------------------------------
    // Read SSM Parameters from FoundationStack
    // --------------------------------------------------------------------------------

    const vpcId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, 'vpc-id'),
    );

    const privateSubnetIdsCsv = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, 'private-subnet-ids'),
    );

    const albSgId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, `sg/${lane}-alb/id`),
    );

    const ecsSgId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, 'sg/ecs/id'),
    );

    const acmRegionalCertArn = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, 'acm/regional-cert-arn'),
    );

    const logBucketId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, 'logging-bucket-id'),
    );

    const logBucketDomain = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, 'logging-bucket-domain'),
    );

    const s3KmsKeyArn = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, 'kms/s3/arn'),
    );

    const hostedZoneId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, 'hosted-zone-id'),
    );

    // ACM certificate for CloudFront (us-east-1)
    // In cdk-deploy mode this could be created by FoundationStack or provided externally
    // For now, read from SSM (must be pre-created or provided via config)
    const acmCloudfrontCertArn = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(config.projectName, config.environment, 'acm/cloudfront-cert-arn'),
    );

    // Parse comma-separated private subnet IDs
    const privateSubnetIds = Fn.split(',', privateSubnetIdsCsv);

    // --------------------------------------------------------------------------------
    // InternalAlb Construct
    // --------------------------------------------------------------------------------

    const alb = new InternalAlb(this, 'InternalAlb', {
      namePrefix: prefix,
      lane,
      vpcId,
      privateSubnetIds: [Fn.select(0, privateSubnetIds), Fn.select(1, privateSubnetIds)],
      albSecurityGroupId: albSgId,
      ecsSecurityGroupId: ecsSgId,
      acmCertificateArn: acmRegionalCertArn,
      logBucketId,
    });

    // --------------------------------------------------------------------------------
    // AssetBucket Construct
    // --------------------------------------------------------------------------------

    const assetBucket = new AssetBucket(this, 'AssetBucket', {
      namePrefix: prefix,
      lane,
      accountId,
      kmsKeyArn: s3KmsKeyArn,
      logBucketId,
    });

    // --------------------------------------------------------------------------------
    // LaneDistribution Construct
    // --------------------------------------------------------------------------------

    new LaneDistribution(this, 'LaneDistribution', {
      namePrefix: prefix,
      lane,
      domainName: config.domainName,
      hostedZoneId,
      albArn: alb.alb.ref,
      albDnsName: alb.alb.attrDnsName,
      albSecurityGroupId: albSgId,
      vpcId,
      s3BucketDomainName: assetBucket.bucket.attrDomainName,
      s3BucketId: assetBucket.bucket.ref,
      oacId: assetBucket.oac.ref,
      acmCloudfrontCertArn,
      logBucketDomainName: logBucketDomain,
      accountId,
    });

    // --------------------------------------------------------------------------------
    // SSM Parameters
    // --------------------------------------------------------------------------------

    putSsmParameter(
      this, 'SsmTargetGroupArn',
      config.projectName, config.environment,
      `target-group/${lane}/arn`, alb.targetGroup.ref,
      `Target Group ARN for ${lane} lane`,
    );

    putSsmParameter(
      this, 'SsmAlbDnsName',
      config.projectName, config.environment,
      `alb/${lane}/dns-name`, alb.alb.attrDnsName,
      `ALB DNS name for ${lane} lane`,
    );

    putSsmParameter(
      this, 'SsmS3BucketArn',
      config.projectName, config.environment,
      `s3-bucket/${lane}/arn`, assetBucket.bucket.attrArn,
      `S3 asset bucket ARN for ${lane} lane`,
    );

    putSsmParameter(
      this, 'SsmS3AccessPolicyArn',
      config.projectName, config.environment,
      `s3-access-policy/${lane}/arn`, assetBucket.s3AccessPolicy.ref,
      `S3 access policy ARN for ${lane} lane`,
    );
  }
}
