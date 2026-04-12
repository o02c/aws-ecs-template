import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface SecurityGroupSetProps {
  vpcId: string;
  securityGroupNames: string[];
  namePrefix: string;
}

export class SecurityGroupSet extends Construct {
  public readonly securityGroups: Record<string, ec2.CfnSecurityGroup>;

  constructor(scope: Construct, id: string, props: SecurityGroupSetProps) {
    super(scope, id);

    // --------------------------------------------------------------------------------
    // Empty Security Group shells (consuming Constructs add rules)
    // --------------------------------------------------------------------------------

    this.securityGroups = {};
    for (const name of props.securityGroupNames) {
      const cfnKey = toPascalCase(name);
      this.securityGroups[name] = new ec2.CfnSecurityGroup(this, `Sg${cfnKey}`, {
        groupDescription: `Security group for ${name}`,
        vpcId: props.vpcId,
        tags: [{ key: 'Name', value: `${props.namePrefix}-${name}` }],
      });
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
