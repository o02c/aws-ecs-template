import { SharedConfig } from '../../lib/helpers/config-types';
import { accounts } from '../accounts';

export const config: SharedConfig = {
  account: accounts.dev,
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
