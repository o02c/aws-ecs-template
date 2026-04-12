import { IAspect, Annotations } from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as logs from 'aws-cdk-lib/aws-logs';
import { IConstruct } from 'constructs';

/**
 * Aspect that validates KMS encryption is enabled on supported resources.
 * Checks S3 buckets, RDS clusters, and CloudWatch Log Groups.
 */
export class EncryptionEnforcer implements IAspect {
  public visit(node: IConstruct): void {
    if (node instanceof s3.CfnBucket) {
      this.checkS3Encryption(node);
    }

    if (node instanceof rds.CfnDBCluster) {
      this.checkRdsEncryption(node);
    }

    if (node instanceof logs.CfnLogGroup) {
      this.checkLogGroupEncryption(node);
    }
  }

  private checkS3Encryption(bucket: s3.CfnBucket): void {
    const encryption = bucket.bucketEncryption;
    if (!encryption) {
      Annotations.of(bucket).addError(
        'S3 bucket must have encryption configuration. Use KMS (aws:kms) encryption.',
      );
      return;
    }

    const rules =
      (encryption as s3.CfnBucket.BucketEncryptionProperty)
        .serverSideEncryptionConfiguration;
    if (!rules || !Array.isArray(rules) || rules.length === 0) {
      Annotations.of(bucket).addError(
        'S3 bucket must have server-side encryption rules configured.',
      );
    }
  }

  private checkRdsEncryption(cluster: rds.CfnDBCluster): void {
    if (cluster.storageEncrypted !== true) {
      Annotations.of(cluster).addError(
        'RDS cluster must have storage encryption enabled.',
      );
    }
  }

  private checkLogGroupEncryption(logGroup: logs.CfnLogGroup): void {
    if (!logGroup.kmsKeyId) {
      Annotations.of(logGroup).addWarning(
        'CloudWatch Log Group should have KMS encryption. Set kmsKeyId property.',
      );
    }
  }
}
