import { Stack } from 'aws-cdk-lib';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';

/**
 * SSM Parameter naming convention for project infrastructure.
 * Pattern: /<project>/<env>/infra/<key>
 */
export function ssmParameterName(project: string, env: string, key: string): string {
  return `/${project}/${env}/infra/${key}`;
}

/**
 * SSM Parameter naming convention for shared infrastructure (read-only).
 * Pattern: /shared/<env>/infra/<key>
 */
export function sharedSsmParameterName(env: string, key: string): string {
  return `/shared/${env}/infra/${key}`;
}

/**
 * Write a string value to SSM Parameter Store.
 */
export function putSsmParameter(
  scope: Construct,
  id: string,
  project: string,
  env: string,
  key: string,
  value: string,
  description?: string,
): ssm.StringParameter {
  return new ssm.StringParameter(scope, id, {
    parameterName: ssmParameterName(project, env, key),
    stringValue: value,
    description,
  });
}
