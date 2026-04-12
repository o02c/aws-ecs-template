import { Construct } from 'constructs';
import * as route53resolver from 'aws-cdk-lib/aws-route53resolver';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface DnsFirewallProps {
  environment: string;
  vpcId: string;
  blockDomains?: string[];
}

export class DnsFirewall extends Construct {
  constructor(scope: Construct, id: string, props: DnsFirewallProps) {
    super(scope, id);

    const prefix = `Shared-${props.environment}`;
    const domains = props.blockDomains ?? [];

    // --------------------------------------------------------------------------------
    // Firewall Domain List
    // --------------------------------------------------------------------------------

    const domainList = new route53resolver.CfnFirewallDomainList(this, 'BlockDomainList', {
      name: `${prefix}-block`,
      domains,
      tags: [{ key: 'Name', value: `${prefix}-block` }],
    });

    // --------------------------------------------------------------------------------
    // Firewall Rule Group
    // --------------------------------------------------------------------------------

    const ruleGroup = new route53resolver.CfnFirewallRuleGroup(this, 'RuleGroup', {
      name: prefix,
      firewallRules: [
        {
          action: 'BLOCK',
          blockResponse: 'NXDOMAIN',
          firewallDomainListId: domainList.attrId,
          priority: 100,
        },
      ],
      tags: [{ key: 'Name', value: prefix }],
    });

    // --------------------------------------------------------------------------------
    // Firewall Rule Group Association to VPC
    // --------------------------------------------------------------------------------

    new route53resolver.CfnFirewallRuleGroupAssociation(this, 'Association', {
      name: prefix,
      firewallRuleGroupId: ruleGroup.attrId,
      vpcId: props.vpcId,
      priority: 101,
      tags: [{ key: 'Name', value: prefix }],
    });
  }
}
