import { Stage, StageProps, Aspects } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { SharedConfig } from '../helpers/config-types';
import { StandardTags } from '../aspects/tagging';
import { EncryptionEnforcer } from '../aspects/encryption';
import { NetworkStack } from '../stacks/network-stack';

export interface SharedStageProps extends StageProps {
  config: SharedConfig;
}

/**
 * SharedStage groups all shared infrastructure stacks.
 * Aspects are applied to all resources within this stage.
 */
export class SharedStage extends Stage {
  constructor(scope: Construct, id: string, props: SharedStageProps) {
    super(scope, id, props);

    // Apply standard tags to all resources in this stage
    Aspects.of(this).add(
      new StandardTags({
        projectName: 'shared',
        environment: props.config.environment,
      }),
    );

    // Enforce encryption on all applicable resources
    Aspects.of(this).add(new EncryptionEnforcer());

    // Network: VPC, TGW, Endpoints, KMS, DNS Firewall
    new NetworkStack(this, 'NetworkStack', {
      stackName: `Shared-${props.config.environment}-Network`,
      description: 'Shared network infrastructure: VPC, TGW, VPC Endpoints, KMS, DNS Firewall',
      config: props.config,
    });
  }
}
