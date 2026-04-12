import { Stage, StageProps, Aspects, StackProps, BootstraplessSynthesizer } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { ProjectConfig } from '../helpers/config-types';
import { StandardTags } from '../aspects/tagging';
import { EncryptionEnforcer } from '../aspects/encryption';
import { resourceName } from '../helpers/naming';
import { FoundationStack } from '../stacks/foundation-stack';
import { DatabaseStack } from '../stacks/database-stack';
import { LaneStack } from '../stacks/lane-stack';
import { ApplicationStack } from '../stacks/application-stack';

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
    const isTemplateOnly = config.deployMode === 'template-only';

    // Helper to create synthesizer props for template-only mode
    // Each stack needs its own BootstraplessSynthesizer instance
    const synthProps = (): Partial<StackProps> =>
      isTemplateOnly ? { synthesizer: new BootstraplessSynthesizer() } : {};

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
    const foundation = new FoundationStack(this, 'FoundationStack', {
      stackName: resourceName(config.projectName, config.environment, 'Foundation'),
      description: 'Foundation infrastructure: KMS, Logging, VPC, SecurityGroups, Route53, DNS Firewall',
      config,
      ...synthProps(),
    });

    // Database: Aurora PostgreSQL Serverless v2
    const database = new DatabaseStack(this, 'DatabaseStack', {
      stackName: resourceName(config.projectName, config.environment, 'Database'),
      description: 'Database infrastructure: Aurora PostgreSQL Serverless v2',
      config,
      ...synthProps(),
    });
    database.addDependency(foundation);

    // Per-lane: ALB, S3 (assets), CloudFront, Route53
    const laneStacks: LaneStack[] = [];
    for (const [laneName] of Object.entries(config.lanes)) {
      const lane = new LaneStack(this, `Lane-${laneName}`, {
        stackName: resourceName(config.projectName, config.environment, `Lane-${laneName}`),
        description: `Lane infrastructure for ${laneName}: ALB, S3, CloudFront, Route53`,
        config,
        lane: laneName,
        ...synthProps(),
      });
      lane.addDependency(foundation);
      laneStacks.push(lane);
    }

    // Application: ECS Cluster, ECR, IAM, Logging, Audit
    const application = new ApplicationStack(this, 'ApplicationStack', {
      stackName: resourceName(config.projectName, config.environment, 'Application'),
      description: 'Application infrastructure: ECS Cluster, ECR, IAM, Logging',
      config,
      ...synthProps(),
    });
    application.addDependency(foundation);
    application.addDependency(database);
    for (const laneStack of laneStacks) {
      application.addDependency(laneStack);
    }
  }
}
