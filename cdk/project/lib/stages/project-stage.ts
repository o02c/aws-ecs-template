import { Stage, StageProps, Aspects } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { ProjectConfig } from '../helpers/config-types';
import { StandardTags } from '../aspects/tagging';
import { EncryptionEnforcer } from '../aspects/encryption';
import { resourceName } from '../helpers/naming';
import { FoundationStack } from '../stacks/foundation-stack';
import { LaneStack } from '../stacks/lane-stack';

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

    // Foundation: KMS, Logging, VPC, SecurityGroups, Route53, DNS Firewall
    new FoundationStack(this, 'FoundationStack', {
      stackName: resourceName(config.projectName, config.environment, 'Foundation'),
      description: 'Foundation infrastructure: KMS, Logging, VPC, SecurityGroups, Route53, DNS Firewall',
      config,
    });

    // Per-lane: ALB, S3 (assets), CloudFront, Route53
    for (const [laneName] of Object.entries(config.lanes)) {
      new LaneStack(this, `Lane-${laneName}`, {
        stackName: resourceName(config.projectName, config.environment, `Lane-${laneName}`),
        description: `Lane infrastructure for ${laneName}: ALB, S3, CloudFront, Route53`,
        config,
        lane: laneName,
      });
    }
  }
}
