import { Stack, StackProps, Fn } from 'aws-cdk-lib';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';
import { ProjectConfig } from '../helpers/config-types';
import { AuroraServerless } from '../constructs/aurora-serverless';
import { putSsmParameter, ssmParameterName } from '../helpers/ssm';

export interface DatabaseStackProps extends StackProps {
  config: ProjectConfig;
}

export class DatabaseStack extends Stack {
  constructor(scope: Construct, id: string, props: DatabaseStackProps) {
    super(scope, id, props);

    const { config } = props;
    const prefix = `${config.projectName}-${config.environment}`;
    const project = config.projectName;
    const env = config.environment;

    // --------------------------------------------------------------------------------
    // Read SSM Parameters from FoundationStack
    // --------------------------------------------------------------------------------

    const vpcId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'vpc-id'),
    );

    const privateSubnetIdsRaw = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'private-subnet-ids'),
    );

    const dbSecurityGroupId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'sg/db/id'),
    );

    const ecsSecurityGroupId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'sg/ecs/id'),
    );

    const kmsKeyArn = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'kms/rds/arn'),
    );

    // Split comma-separated subnet IDs into list
    const privateSubnetIds = Fn.split(',', privateSubnetIdsRaw);

    // --------------------------------------------------------------------------------
    // AuroraServerless Construct
    // --------------------------------------------------------------------------------

    const aurora = new AuroraServerless(this, 'Aurora', {
      namePrefix: prefix,
      vpcId,
      privateSubnetIds,
      dbSecurityGroupId,
      ecsSecurityGroupId,
      kmsKeyArn,
      deletionProtection: config.database.deletionProtection,
      skipFinalSnapshot: config.database.skipFinalSnapshot,
    });

    // --------------------------------------------------------------------------------
    // SSM Parameters
    // --------------------------------------------------------------------------------

    putSsmParameter(
      this, 'SsmDbClusterArn',
      project, env,
      'db/cluster-arn', aurora.clusterArn,
      'Aurora cluster ARN',
    );

    putSsmParameter(
      this, 'SsmDbClusterResourceId',
      project, env,
      'db/cluster-resource-id', aurora.clusterResourceId,
      'Aurora cluster resource ID',
    );

    putSsmParameter(
      this, 'SsmDbRdsIamAuthPolicyArn',
      project, env,
      'db/rds-iam-auth-policy-arn', aurora.rdsIamAuthPolicyArn,
      'RDS IAM auth policy ARN',
    );
  }
}
