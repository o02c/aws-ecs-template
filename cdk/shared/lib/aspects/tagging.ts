import { IAspect, Tags } from 'aws-cdk-lib';
import { IConstruct } from 'constructs';

export interface StandardTagsProps {
  projectName: string;
  environment: string;
}

/**
 * Aspect that applies standard tags to all resources in the scope.
 * Equivalent to Terraform's default_tags in the AWS provider.
 */
export class StandardTags implements IAspect {
  private readonly projectName: string;
  private readonly environment: string;

  constructor(props: StandardTagsProps) {
    this.projectName = props.projectName;
    this.environment = props.environment;
  }

  public visit(node: IConstruct): void {
    Tags.of(node).add('ProjectName', this.projectName);
    Tags.of(node).add('Environment', this.environment);
    Tags.of(node).add('ManagedBy', 'cdk');
  }
}
