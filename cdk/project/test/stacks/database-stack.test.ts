import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { DatabaseStack } from '../../lib/stacks/database-stack';
import { ProjectConfig } from '../../lib/helpers/config-types';

const testConfig: ProjectConfig = {
  account: { accountId: '123456789012', region: 'ap-northeast-1' },
  projectName: 'myapp',
  environment: 'dev',
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
    deletionProtection: false,
    skipFinalSnapshot: true,
  },
  enableCicd: false,
  enableDnsFirewall: true,
  deployMode: 'cdk-deploy',
};

describe('DatabaseStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new DatabaseStack(app, 'TestDatabaseStack', {
      config: testConfig,
      env: { account: testConfig.account.accountId, region: testConfig.account.region },
    });
    template = Template.fromStack(stack);
  });

  // --------------------------------------------------------------------------------
  // Aurora Cluster
  // --------------------------------------------------------------------------------

  test('creates Aurora PostgreSQL cluster with Serverless v2 scaling', () => {
    template.hasResourceProperties('AWS::RDS::DBCluster', {
      Engine: 'aurora-postgresql',
      EngineVersion: '16.4',
      EngineMode: 'provisioned',
      DatabaseName: 'app',
      DBClusterIdentifier: 'myapp-dev',
      ManageMasterUserPassword: true,
      EnableIAMDatabaseAuthentication: true,
      StorageEncrypted: true,
      DeletionProtection: false,
      BackupRetentionPeriod: 7,
      ServerlessV2ScalingConfiguration: {
        MinCapacity: 0.5,
        MaxCapacity: 4,
      },
    });
  });

  test('cluster has managed master user secret with KMS', () => {
    template.hasResourceProperties('AWS::RDS::DBCluster', {
      MasterUserSecret: Match.objectLike({
        KmsKeyId: Match.anyValue(),
      }),
    });
  });

  // --------------------------------------------------------------------------------
  // Aurora Instances
  // --------------------------------------------------------------------------------

  test('creates writer and reader instances with db.serverless class', () => {
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      DBInstanceIdentifier: 'myapp-dev-writer',
      DBInstanceClass: 'db.serverless',
      Engine: 'aurora-postgresql',
    });
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      DBInstanceIdentifier: 'myapp-dev-reader',
      DBInstanceClass: 'db.serverless',
      Engine: 'aurora-postgresql',
    });
  });

  test('creates exactly 2 DB instances', () => {
    template.resourceCountIs('AWS::RDS::DBInstance', 2);
  });

  // --------------------------------------------------------------------------------
  // Parameter Groups
  // --------------------------------------------------------------------------------

  test('creates cluster parameter group with rds.force_ssl = 1', () => {
    template.hasResourceProperties('AWS::RDS::DBClusterParameterGroup', {
      Family: 'aurora-postgresql16',
      Parameters: {
        'rds.force_ssl': '1',
      },
    });
  });

  test('creates DB parameter group for aurora-postgresql16', () => {
    template.hasResourceProperties('AWS::RDS::DBParameterGroup', {
      Family: 'aurora-postgresql16',
    });
  });

  // --------------------------------------------------------------------------------
  // Subnet Group
  // --------------------------------------------------------------------------------

  test('creates DB subnet group', () => {
    template.hasResourceProperties('AWS::RDS::DBSubnetGroup', {
      DBSubnetGroupName: 'myapp-dev',
    });
  });

  // --------------------------------------------------------------------------------
  // Security Group Rule
  // --------------------------------------------------------------------------------

  test('creates ingress rule for PostgreSQL (5432) from ECS SG', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroupIngress', {
      IpProtocol: 'tcp',
      FromPort: 5432,
      ToPort: 5432,
      Description: 'PostgreSQL from ECS',
    });
  });

  // --------------------------------------------------------------------------------
  // IAM Policy
  // --------------------------------------------------------------------------------

  test('creates IAM policy for rds-db:connect', () => {
    template.hasResourceProperties('AWS::IAM::ManagedPolicy', {
      ManagedPolicyName: 'myapp-dev-rds-iam-auth',
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Effect: 'Allow',
            Action: 'rds-db:connect',
          }),
        ]),
      }),
    });
  });

  // --------------------------------------------------------------------------------
  // SSM Parameters
  // --------------------------------------------------------------------------------

  test('creates SSM Parameters for cross-stack references', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/db/cluster-arn',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/db/cluster-resource-id',
    });
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/myapp/dev/infra/db/rds-iam-auth-policy-arn',
    });
  });
});

describe('DatabaseStack - production config', () => {
  test('sets deletion protection when enabled', () => {
    const app = new cdk.App();
    const prodConfig = {
      ...testConfig,
      environment: 'prod',
      database: {
        deletionProtection: true,
        skipFinalSnapshot: false,
      },
    };
    const stack = new DatabaseStack(app, 'TestDatabaseStackProd', {
      config: prodConfig,
      env: { account: testConfig.account.accountId, region: testConfig.account.region },
    });
    const tmpl = Template.fromStack(stack);
    tmpl.hasResourceProperties('AWS::RDS::DBCluster', {
      DeletionProtection: true,
    });
  });
});
