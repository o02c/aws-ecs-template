import { Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { SharedConfig } from '../helpers/config-types';
import { putSsmParameter } from '../helpers/ssm';

export interface IamStackProps extends StackProps {
  config: SharedConfig;
}

/**
 * IamStack manages shared IAM resources (users, groups, policies).
 *
 * Currently empty - IAM users/groups will be added here as needed.
 * Mirrors terraform/shared/modules/iam/ which also has empty maps.
 */
export class IamStack extends Stack {
  constructor(scope: Construct, id: string, props: IamStackProps) {
    super(scope, id, props);

    const { config } = props;

    // --------------------------------------------------------------------------------
    // IAM Users / Groups
    // --------------------------------------------------------------------------------
    // TODO: Add IAM users and groups here when needed.
    // Example:
    //   new iam.User(this, 'UserName', { userName: 'name', path: '/' });
    //   new iam.Group(this, 'GroupName', { groupName: 'name' });

    // --------------------------------------------------------------------------------
    // SSM Parameter (stack deployment marker)
    // --------------------------------------------------------------------------------

    putSsmParameter(
      this,
      'SsmIamStackDeployed',
      config.environment,
      'iam-stack-deployed',
      'true',
      'Marker indicating IamStack has been deployed',
    );
  }
}
