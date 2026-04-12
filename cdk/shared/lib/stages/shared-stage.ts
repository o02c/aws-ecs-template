import { Stack, Stage, StageProps, Aspects } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { SharedConfig } from '../helpers/config-types';
import { StandardTags } from '../aspects/tagging';
import { EncryptionEnforcer } from '../aspects/encryption';

export interface SharedStageProps extends StageProps {
  config: SharedConfig;
}

/**
 * SharedStage groups all shared infrastructure stacks.
 * Stacks will be added in subsequent PRs (NetworkStack, IamStack).
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

    // Placeholder stack - will be replaced by NetworkStack and IamStack
    new Stack(this, 'PlaceholderStack', {
      stackName: `Shared-${props.config.environment}-Placeholder`,
      description: 'Placeholder stack. Will be removed when real stacks are added.',
    });
  }
}
