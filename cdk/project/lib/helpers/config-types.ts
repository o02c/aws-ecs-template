export interface AccountConfig {
  accountId: string;
  region: string;
}

export interface LaneConfig {
  identifier: string;
}

export interface ServiceConfig {
  lane: string;
}

export interface ProjectConfig {
  account: AccountConfig;
  projectName: string;
  environment: string;
  vpcCidr: string;
  azs: string[];
  privateSubnets: Record<string, string>;
  domainName: string;
  lanes: Record<string, LaneConfig>;
  services: Record<string, ServiceConfig>;
  database: {
    deletionProtection: boolean;
    skipFinalSnapshot: boolean;
  };
  enableCicd: boolean;
  enableDnsFirewall: boolean;
  deployMode: 'cdk-deploy' | 'template-only';
}
