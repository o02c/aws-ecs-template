import { Stack, StackProps, Stage, StageProps, Aspects } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { ProjectConfig } from '../helpers/config-types';
import { StandardTags } from '../aspects/tagging';
import { EncryptionEnforcer } from '../aspects/encryption';
import { resourceName } from '../helpers/naming';

export interface ProjectStageProps extends StageProps {
  config: ProjectConfig;
}

/**
 * ProjectStage groups all project infrastructure stacks.
 * Aspects are applied to all resources within this stage.
 */
export class ProjectStage extends Stage {
  constructor(scope: Construct, id: string, props: ProjectStageProps) {
    super(scope, id, props);

    const { config } = props;

    // Apply standard tags to all resources in this stage
    Aspects.of(this).add(
      new StandardTags({
        projectName: config.projectName,
        environment: config.environment,
      }),
    );

    // Enforce encryption on all applicable resources
    Aspects.of(this).add(new EncryptionEnforcer());

    // Placeholder stack - will be replaced by real stacks in P5+
    new Stack(this, 'PlaceholderStack', {
      stackName: resourceName(config.projectName, config.environment, 'Placeholder'),
      description: 'Placeholder stack for project initialization (will be removed)',
    });
  }
}
