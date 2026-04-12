export interface AccountConfig {
  accountId: string;
  region: string;
}

export interface SharedConfig {
  account: AccountConfig;
  environment: string;
  vpcCidr: string;
  azs: string[];
  publicSubnets: Record<string, string>;
  privateSubnets: Record<string, string>;
  interfaceEndpoints: Record<string, string>;
  projectVpcCidrs: Record<string, string>;
}
