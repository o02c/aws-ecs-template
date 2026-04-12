import { ProjectConfig } from '../../lib/helpers/config-types';
import { accounts } from '../accounts';

export const config: ProjectConfig = {
  account: accounts.dev,
  projectName: 'myapp',
  environment: 'dev',
  vpcCidr: '10.1.0.0/16',
  azs: ['ap-northeast-1a', 'ap-northeast-1c'],
  privateSubnets: {
    'ap-northeast-1a': '10.1.11.0/24',
    'ap-northeast-1c': '10.1.12.0/24',
  },
  domainName: 'o2c.click',
  lanes: {
    user: { identifier: 'user' },
    admin: { identifier: 'admin' },
  },
  services: {
    'user-api': { lane: 'user' },
    'admin-api': { lane: 'admin' },
  },
  database: {
    deletionProtection: false,
    skipFinalSnapshot: true,
  },
  enableCicd: false,
  enableDnsFirewall: true,
  deployMode: 'cdk-deploy',
};
