import { Stack, StackProps, Fn } from 'aws-cdk-lib';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';
import { ProjectConfig } from '../helpers/config-types';
import { Application } from '../constructs/application';
import { putSsmParameter, ssmParameterName, sharedSsmParameterName } from '../helpers/ssm';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface ApplicationStackProps extends StackProps {
  config: ProjectConfig;
}

export class ApplicationStack extends Stack {
  constructor(scope: Construct, id: string, props: ApplicationStackProps) {
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

    const privateSubnetIdsCsv = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'private-subnet-ids'),
    );

    const ecsSecurityGroupId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'sg/ecs/id'),
    );

    const dbSecurityGroupId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'sg/db/id'),
    );

    const logsKmsKeyArn = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'kms/logs/arn'),
    );

    const s3KmsKeyArn = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'kms/s3/arn'),
    );

    const logBucketId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'logging-bucket-id'),
    );

    // --------------------------------------------------------------------------------
    // Read SSM Parameters from DatabaseStack
    // --------------------------------------------------------------------------------

    const dbClusterArn = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'db/cluster-arn'),
    );

    const dbClusterResourceId = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'db/cluster-resource-id'),
    );

    const rdsIamAuthPolicyArn = ssm.StringParameter.valueForStringParameter(
      this,
      ssmParameterName(project, env, 'db/rds-iam-auth-policy-arn'),
    );

    // --------------------------------------------------------------------------------
    // Read SSM Parameters from LaneStack (per lane)
    // --------------------------------------------------------------------------------

    const albSecurityGroupIds: Record<string, string> = {};
    const s3BucketArns: Record<string, string> = {};
    const s3AccessPolicyArns: Record<string, string> = {};

    for (const laneName of Object.keys(config.lanes)) {
      albSecurityGroupIds[laneName] = ssm.StringParameter.valueForStringParameter(
        this,
        ssmParameterName(project, env, `sg/${laneName}-alb/id`),
      );

      s3BucketArns[laneName] = ssm.StringParameter.valueForStringParameter(
        this,
        ssmParameterName(project, env, `s3-bucket/${laneName}/arn`),
      );

      s3AccessPolicyArns[laneName] = ssm.StringParameter.valueForStringParameter(
        this,
        ssmParameterName(project, env, `s3-access-policy/${laneName}/arn`),
      );
    }

    // --------------------------------------------------------------------------------
    // Read SSM Parameters from Shared infrastructure
    // --------------------------------------------------------------------------------

    const sharedPrivateSubnetCidrs = ssm.StringParameter.valueForStringParameter(
      this,
      sharedSsmParameterName(env, 'private-subnet-cidrs'),
    );

    // Parse private subnet IDs
    const privateSubnetIds = Fn.split(',', privateSubnetIdsCsv);

    // --------------------------------------------------------------------------------
    // Application Construct
    // --------------------------------------------------------------------------------

    const application = new Application(this, 'Application', {
      namePrefix: prefix,
      projectName: project,
      environment: env,
      services: config.services,
      lanes: config.lanes,
      vpcId,
      privateSubnetIds,
      ecsSecurityGroupId,
      dbSecurityGroupId,
      albSecurityGroupIds,
      logsKmsKeyArn,
      s3KmsKeyArn,
      dbClusterArn,
      dbClusterResourceId,
      rdsIamAuthPolicyArn,
      s3BucketArns,
      s3AccessPolicyArns,
      logBucketId,
      sharedPrivateSubnetCidrs,
    });

    // --------------------------------------------------------------------------------
    // SSM Parameters (for ecspresso)
    // --------------------------------------------------------------------------------

    putSsmParameter(
      this, 'SsmEcsClusterName',
      project, env,
      'ecs-cluster-name', application.cluster.ref,
      'ECS Cluster name',
    );

    putSsmParameter(
      this, 'SsmTaskExecutionRoleArn',
      project, env,
      'task-execution-role-arn', application.taskExecutionRole.attrArn,
      'ECS Task Execution Role ARN',
    );

    for (const serviceName of Object.keys(config.services)) {
      const cfnName = toPascalCase(serviceName);

      putSsmParameter(
        this, `SsmEcr${cfnName}Url`,
        project, env,
        `ecr/${serviceName}/url`, application.ecrRepositories[serviceName].attrRepositoryUri,
        `ECR repository URL for ${serviceName}`,
      );

      putSsmParameter(
        this, `SsmTaskRole${cfnName}Arn`,
        project, env,
        `task-role/${serviceName}/arn`, application.taskRoles[serviceName].attrArn,
        `ECS Task Role ARN for ${serviceName}`,
      );
    }
  }
}

// --------------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------------

function toPascalCase(s: string): string {
  return s
    .split('-')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}
