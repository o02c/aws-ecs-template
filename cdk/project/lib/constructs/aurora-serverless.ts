import { Construct } from 'constructs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Stack } from 'aws-cdk-lib';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface AuroraServerlessProps {
  namePrefix: string;
  vpcId: string;
  privateSubnetIds: string[];
  dbSecurityGroupId: string;
  ecsSecurityGroupId: string;
  kmsKeyArn: string;
  deletionProtection: boolean;
  skipFinalSnapshot: boolean;
  databaseName?: string;
}

export class AuroraServerless extends Construct {
  public readonly clusterArn: string;
  public readonly clusterResourceId: string;
  public readonly clusterEndpoint: string;
  public readonly readerEndpoint: string;
  public readonly rdsIamAuthPolicyArn: string;

  constructor(scope: Construct, id: string, props: AuroraServerlessProps) {
    super(scope, id);

    const {
      namePrefix,
      privateSubnetIds,
      dbSecurityGroupId,
      ecsSecurityGroupId,
      kmsKeyArn,
      deletionProtection,
      skipFinalSnapshot,
      databaseName = 'app',
    } = props;

    const stack = Stack.of(this);
    const region = stack.region;
    const accountId = stack.account;

    // --------------------------------------------------------------------------------
    // DB Subnet Group
    // --------------------------------------------------------------------------------

    const subnetGroup = new rds.CfnDBSubnetGroup(this, 'SubnetGroup', {
      dbSubnetGroupDescription: `${namePrefix} Aurora subnet group`,
      dbSubnetGroupName: namePrefix,
      subnetIds: privateSubnetIds,
      tags: [{ key: 'Name', value: namePrefix }],
    });

    // --------------------------------------------------------------------------------
    // Cluster Parameter Group (aurora-postgresql16, rds.force_ssl = 1)
    // --------------------------------------------------------------------------------

    const clusterParameterGroup = new rds.CfnDBClusterParameterGroup(this, 'ClusterParameterGroup', {
      description: `${namePrefix} cluster parameter group`,
      family: 'aurora-postgresql16',
      parameters: {
        'rds.force_ssl': '1',
      },
      tags: [{ key: 'Name', value: `${namePrefix}-cluster` }],
    });

    // --------------------------------------------------------------------------------
    // DB Parameter Group (aurora-postgresql16)
    // --------------------------------------------------------------------------------

    const dbParameterGroup = new rds.CfnDBParameterGroup(this, 'DbParameterGroup', {
      description: `${namePrefix} instance parameter group`,
      family: 'aurora-postgresql16',
      tags: [{ key: 'Name', value: `${namePrefix}-instance` }],
    });

    // --------------------------------------------------------------------------------
    // Security Group Rule: PostgreSQL (5432) ingress from ECS
    // --------------------------------------------------------------------------------

    new ec2.CfnSecurityGroupIngress(this, 'DbFromEcs', {
      groupId: dbSecurityGroupId,
      ipProtocol: 'tcp',
      fromPort: 5432,
      toPort: 5432,
      sourceSecurityGroupId: ecsSecurityGroupId,
      description: 'PostgreSQL from ECS',
    });

    // --------------------------------------------------------------------------------
    // Aurora PostgreSQL Cluster (Serverless v2, provisioned mode)
    // --------------------------------------------------------------------------------

    const cluster = new rds.CfnDBCluster(this, 'Cluster', {
      engine: 'aurora-postgresql',
      engineVersion: '16.4',
      engineMode: 'provisioned',
      databaseName,
      dbClusterIdentifier: namePrefix,
      masterUsername: 'postgres',
      manageMasterUserPassword: true,
      masterUserSecret: {
        kmsKeyId: kmsKeyArn,
      },
      dbClusterParameterGroupName: clusterParameterGroup.ref,
      dbSubnetGroupName: subnetGroup.ref,
      vpcSecurityGroupIds: [dbSecurityGroupId],
      enableIamDatabaseAuthentication: true,
      storageEncrypted: true,
      kmsKeyId: kmsKeyArn,
      deletionProtection,
      backupRetentionPeriod: 7,
      serverlessV2ScalingConfiguration: {
        minCapacity: 0.5,
        maxCapacity: 4,
      },
      tags: [{ key: 'Name', value: namePrefix }],
    });

    // Conditionally set skip/final snapshot
    if (skipFinalSnapshot) {
      cluster.addPropertyOverride('SkipFinalSnapshot', true);
    } else {
      cluster.addPropertyOverride('FinalSnapshotIdentifier', `${namePrefix}-final`);
    }

    // --------------------------------------------------------------------------------
    // Aurora Instances (Writer + Reader)
    // --------------------------------------------------------------------------------

    const instances: Record<string, rds.CfnDBInstance> = {};
    for (const role of ['writer', 'reader']) {
      instances[role] = new rds.CfnDBInstance(this, `Instance${capitalize(role)}`, {
        dbInstanceIdentifier: `${namePrefix}-${role}`,
        dbClusterIdentifier: cluster.ref,
        dbInstanceClass: 'db.serverless',
        engine: 'aurora-postgresql',
        engineVersion: '16.4',
        dbParameterGroupName: dbParameterGroup.ref,
        tags: [{ key: 'Name', value: `${namePrefix}-${role}` }],
      });
    }

    // --------------------------------------------------------------------------------
    // IAM Policy: rds-db:connect for app user
    // --------------------------------------------------------------------------------

    const rdsIamAuthPolicy = new iam.CfnManagedPolicy(this, 'RdsIamAuthPolicy', {
      managedPolicyName: `${namePrefix}-rds-iam-auth`,
      description: 'Allow IAM authentication to Aurora cluster',
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: 'rds-db:connect',
            Resource: {
              'Fn::Sub': [
                'arn:aws:rds-db:${Region}:${AccountId}:dbuser:${ClusterResourceId}/app',
                {
                  Region: region,
                  AccountId: accountId,
                  ClusterResourceId: cluster.attrDbClusterResourceId,
                },
              ],
            },
          },
        ],
      },
    });

    // --------------------------------------------------------------------------------
    // Outputs
    // --------------------------------------------------------------------------------

    this.clusterArn = cluster.attrDbClusterArn;
    this.clusterResourceId = cluster.attrDbClusterResourceId;
    this.clusterEndpoint = cluster.attrEndpointAddress;
    this.readerEndpoint = cluster.attrReadEndpointAddress;
    this.rdsIamAuthPolicyArn = rdsIamAuthPolicy.ref;
  }
}

// --------------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------------

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
