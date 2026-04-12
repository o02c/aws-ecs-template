import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { StandardTags } from '../../lib/aspects/tagging';

describe('StandardTags Aspect', () => {
  test('applies ProjectName, Environment, and ManagedBy tags', () => {
    const app = new cdk.App();
    const stack = new cdk.Stack(app, 'TestStack');

    // Create a taggable resource
    new s3.Bucket(stack, 'TestBucket', {
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    // Apply the aspect
    cdk.Aspects.of(stack).add(
      new StandardTags({
        projectName: 'shared',
        environment: 'dev',
      }),
    );

    const template = Template.fromStack(stack);

    template.hasResourceProperties('AWS::S3::Bucket', {
      Tags: [
        { Key: 'Environment', Value: 'dev' },
        { Key: 'ManagedBy', Value: 'cdk' },
        { Key: 'ProjectName', Value: 'shared' },
      ],
    });
  });

  test('tags are applied to multiple resources', () => {
    const app = new cdk.App();
    const stack = new cdk.Stack(app, 'TestStack');

    new s3.Bucket(stack, 'Bucket1', {
      encryption: s3.BucketEncryption.S3_MANAGED,
    });
    new s3.Bucket(stack, 'Bucket2', {
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    cdk.Aspects.of(stack).add(
      new StandardTags({
        projectName: 'myapp',
        environment: 'prod',
      }),
    );

    const template = Template.fromStack(stack);

    // Both buckets should have tags
    const buckets = template.findResources('AWS::S3::Bucket');
    expect(Object.keys(buckets)).toHaveLength(2);

    for (const key of Object.keys(buckets)) {
      const tags = buckets[key].Properties.Tags;
      expect(tags).toEqual(
        expect.arrayContaining([
          { Key: 'ProjectName', Value: 'myapp' },
          { Key: 'Environment', Value: 'prod' },
          { Key: 'ManagedBy', Value: 'cdk' },
        ]),
      );
    }
  });
});
