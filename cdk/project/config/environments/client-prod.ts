import { ProjectConfig } from '../../lib/helpers/config-types';

export const config: ProjectConfig = {
  account: {
    accountId: '999999999999',
    region: 'ap-northeast-1',
  },
  projectName: 'myapp',
  environment: 'prod',
  vpcCidr: '10.1.0.0/16',
  azs: ['ap-northeast-1a', 'ap-northeast-1c'],
  privateSubnets: {
    'ap-northeast-1a': '10.1.11.0/24',
    'ap-northeast-1c': '10.1.12.0/24',
  },
  domainName: 'example.com',
  lanes: {
    user: { identifier: 'user' },
    admin: { identifier: 'admin' },
  },
  services: {
    'user-api': { lane: 'user' },
    'admin-api': { lane: 'admin' },
  },
  database: {
    deletionProtection: true,
    skipFinalSnapshot: false,
  },
  enableCicd: false,
  enableDnsFirewall: true,
  deployMode: 'template-only',
};
