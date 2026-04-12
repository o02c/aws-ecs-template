import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { IamStack } from '../../lib/stacks/iam-stack';
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

describe('IamStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new IamStack(app, 'TestIamStack', {
      config: testConfig,
      env: { account: testConfig.account.accountId, region: testConfig.account.region },
    });
    template = Template.fromStack(stack);
  });

  // --------------------------------------------------------------------------------
  // SSM Parameter (deployment marker)
  // --------------------------------------------------------------------------------

  test('creates SSM Parameter as deployment marker', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/shared/dev/infra/iam-stack-deployed',
      Type: 'String',
      Value: 'true',
    });
  });

  test('SSM Parameter count is 1', () => {
    template.resourceCountIs('AWS::SSM::Parameter', 1);
  });

  // --------------------------------------------------------------------------------
  // IAM Resources (currently empty)
  // --------------------------------------------------------------------------------

  test('no IAM users created (empty state)', () => {
    template.resourceCountIs('AWS::IAM::User', 0);
  });

  test('no IAM groups created (empty state)', () => {
    template.resourceCountIs('AWS::IAM::Group', 0);
  });
});
