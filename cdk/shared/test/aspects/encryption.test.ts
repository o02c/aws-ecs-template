import * as cdk from 'aws-cdk-lib';
import { Annotations, Match } from 'aws-cdk-lib/assertions';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as kms from 'aws-cdk-lib/aws-kms';
import { EncryptionEnforcer } from '../../lib/aspects/encryption';

describe('EncryptionEnforcer Aspect', () => {
  let app: cdk.App;
  let stack: cdk.Stack;

  beforeEach(() => {
    app = new cdk.App();
    stack = new cdk.Stack(app, 'TestStack');
  });

  describe('S3 Bucket', () => {
    test('no error when encryption is configured', () => {
      new s3.Bucket(stack, 'EncryptedBucket', {
        encryption: s3.BucketEncryption.S3_MANAGED,
      });

      cdk.Aspects.of(stack).add(new EncryptionEnforcer());

      const annotations = Annotations.fromStack(stack);
      annotations.hasNoError('/TestStack/EncryptedBucket/Resource', Match.anyValue());
    });

    test('error when encryption is not configured', () => {
      // Use L1 construct to create bucket without encryption
      new s3.CfnBucket(stack, 'UnencryptedBucket', {});

      cdk.Aspects.of(stack).add(new EncryptionEnforcer());

      const annotations = Annotations.fromStack(stack);
      annotations.hasError(
        '/TestStack/UnencryptedBucket',
        Match.stringLikeRegexp('S3 bucket must have encryption'),
      );
    });
  });

  describe('RDS Cluster', () => {
    test('no error when storage encryption is enabled', () => {
      new rds.CfnDBCluster(stack, 'EncryptedCluster', {
        engine: 'aurora-postgresql',
        storageEncrypted: true,
      });

      cdk.Aspects.of(stack).add(new EncryptionEnforcer());

      const annotations = Annotations.fromStack(stack);
      annotations.hasNoError('/TestStack/EncryptedCluster', Match.anyValue());
    });

    test('error when storage encryption is not enabled', () => {
      new rds.CfnDBCluster(stack, 'UnencryptedCluster', {
        engine: 'aurora-postgresql',
      });

      cdk.Aspects.of(stack).add(new EncryptionEnforcer());

      const annotations = Annotations.fromStack(stack);
      annotations.hasError(
        '/TestStack/UnencryptedCluster',
        Match.stringLikeRegexp('RDS cluster must have storage encryption'),
      );
    });
  });

  describe('CloudWatch Log Group', () => {
    test('no warning when KMS key is set', () => {
      const key = new kms.Key(stack, 'Key');
      new logs.LogGroup(stack, 'EncryptedLogGroup', {
        encryptionKey: key,
      });

      cdk.Aspects.of(stack).add(new EncryptionEnforcer());

      const annotations = Annotations.fromStack(stack);
      annotations.hasNoWarning(
        '/TestStack/EncryptedLogGroup/Resource',
        Match.anyValue(),
      );
    });

    test('warning when KMS key is not set', () => {
      new logs.CfnLogGroup(stack, 'UnencryptedLogGroup', {});

      cdk.Aspects.of(stack).add(new EncryptionEnforcer());

      const annotations = Annotations.fromStack(stack);
      annotations.hasWarning(
        '/TestStack/UnencryptedLogGroup',
        Match.stringLikeRegexp('CloudWatch Log Group should have KMS encryption'),
      );
    });
  });
});
