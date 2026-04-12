#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ProjectStage } from '../lib/stages/project-stage';
import { ProjectConfig } from '../lib/helpers/config-types';

const app = new cdk.App();

// Resolve environment from CDK context: -c env=dev
const envName = app.node.tryGetContext('env');
if (!envName) {
  throw new Error('Context variable "env" is required. Use: cdk synth -c env=dev');
}

// Dynamic import of environment config
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { config } = require(`../config/environments/${envName}`) as { config: ProjectConfig };

new ProjectStage(app, `${config.projectName}-${config.environment}`, {
  config,
  env: {
    account: config.account.accountId,
    region: config.account.region,
  },
});
