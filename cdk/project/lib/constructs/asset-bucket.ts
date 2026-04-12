import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as iam from 'aws-cdk-lib/aws-iam';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface AssetBucketProps {
  namePrefix: string;
  lane: string;
  accountId: string;
  kmsKeyArn: string;
  logBucketId: string;
}

export class AssetBucket extends Construct {
  public readonly bucket: s3.CfnBucket;
  public readonly oac: cloudfront.CfnOriginAccessControl;
  public readonly s3AccessPolicy: iam.CfnManagedPolicy;

  constructor(scope: Construct, id: string, props: AssetBucketProps) {
    super(scope, id);

    const bucketName = `${props.namePrefix}-${props.lane}-assets-${props.accountId}`;

    // --------------------------------------------------------------------------------
    // S3 Bucket
    // --------------------------------------------------------------------------------

    this.bucket = new s3.CfnBucket(this, 'Bucket', {
      bucketName,
      versioningConfiguration: { status: 'Enabled' },
      bucketEncryption: {
        serverSideEncryptionConfiguration: [
          {
            serverSideEncryptionByDefault: {
              sseAlgorithm: 'aws:kms',
              kmsMasterKeyId: props.kmsKeyArn,
            },
            bucketKeyEnabled: true,
          },
        ],
      },
      publicAccessBlockConfiguration: {
        blockPublicAcls: true,
        blockPublicPolicy: true,
        ignorePublicAcls: true,
        restrictPublicBuckets: true,
      },
      loggingConfiguration: {
        destinationBucketName: props.logBucketId,
        logFilePrefix: `s3/${props.lane}/`,
      },
      tags: [{ key: 'Name', value: `${props.namePrefix}-${props.lane}-assets` }],
    });

    // --------------------------------------------------------------------------------
    // Bucket Policy (deny insecure transport)
    // Note: CloudFront OAC GetObject is added by LaneDistribution after distribution creation
    // --------------------------------------------------------------------------------

    const bucketArn = `arn:aws:s3:::${bucketName}`;

    new s3.CfnBucketPolicy(this, 'BucketPolicy', {
      bucket: this.bucket.ref,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Sid: 'DenyInsecureTransport',
            Effect: 'Deny',
            Principal: '*',
            Action: 's3:*',
            Resource: [bucketArn, `${bucketArn}/*`],
            Condition: {
              Bool: { 'aws:SecureTransport': 'false' },
            },
          },
        ],
      },
    });

    // --------------------------------------------------------------------------------
    // CloudFront Origin Access Control (OAC, SigV4)
    // --------------------------------------------------------------------------------

    this.oac = new cloudfront.CfnOriginAccessControl(this, 'Oac', {
      originAccessControlConfig: {
        name: `${props.namePrefix}-${props.lane}`,
        description: `OAC for ${props.lane} S3 bucket`,
        originAccessControlOriginType: 's3',
        signingBehavior: 'always',
        signingProtocol: 'sigv4',
      },
    });

    // --------------------------------------------------------------------------------
    // IAM Policy (GetObject, PutObject for ECS task)
    // --------------------------------------------------------------------------------

    this.s3AccessPolicy = new iam.CfnManagedPolicy(this, 'S3AccessPolicy', {
      managedPolicyName: `${props.namePrefix}-${props.lane}-s3-access`,
      description: `Allow ECS tasks to access ${props.lane} S3 bucket`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: ['s3:GetObject', 's3:PutObject'],
            Resource: [bucketArn, `${bucketArn}/*`],
          },
        ],
      },
    });
  }
}
