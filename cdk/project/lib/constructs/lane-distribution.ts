import { Fn } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as s3 from 'aws-cdk-lib/aws-s3';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface LaneDistributionProps {
  namePrefix: string;
  lane: string;
  domainName: string;
  hostedZoneId: string;
  albArn: string;
  albDnsName: string;
  albSecurityGroupId: string;
  vpcId: string;
  s3BucketDomainName: string;
  s3BucketId: string;
  oacId: string;
  acmCloudfrontCertArn: string;
  logBucketDomainName: string;
  accountId: string;
}

export class LaneDistribution extends Construct {
  public readonly distribution: cloudfront.CfnDistribution;
  public readonly vpcOrigin: cloudfront.CfnVpcOrigin;

  constructor(scope: Construct, id: string, props: LaneDistributionProps) {
    super(scope, id);

    const name = `${props.namePrefix}-${props.lane}`;
    const laneFqdn = `${props.lane}.${props.domainName}`;

    // --------------------------------------------------------------------------------
    // VPC Origin (Internal ALB)
    // --------------------------------------------------------------------------------

    this.vpcOrigin = new cloudfront.CfnVpcOrigin(this, 'VpcOrigin', {
      vpcOriginEndpointConfig: {
        name: `${name}-alb`,
        arn: props.albArn,
        httpPort: 80,
        httpsPort: 443,
        originProtocolPolicy: 'https-only',
        originSslProtocols: ['TLSv1.2'],
      },
      tags: [{ key: 'Name', value: `${name}-alb-origin` }],
    });

    // --------------------------------------------------------------------------------
    // Cache Policy for Static Assets
    // --------------------------------------------------------------------------------

    const staticCachePolicy = new cloudfront.CfnCachePolicy(this, 'StaticCachePolicy', {
      cachePolicyConfig: {
        name: `${name}-static`,
        comment: `Cache policy for ${props.lane} static assets`,
        defaultTtl: 86400,
        maxTtl: 31536000,
        minTtl: 0,
        parametersInCacheKeyAndForwardedToOrigin: {
          cookiesConfig: { cookieBehavior: 'none' },
          headersConfig: { headerBehavior: 'none' },
          queryStringsConfig: { queryStringBehavior: 'none' },
          enableAcceptEncodingGzip: true,
          enableAcceptEncodingBrotli: true,
        },
      },
    });

    // --------------------------------------------------------------------------------
    // CloudFront Distribution
    // --------------------------------------------------------------------------------

    this.distribution = new cloudfront.CfnDistribution(this, 'Distribution', {
      distributionConfig: {
        enabled: true,
        ipv6Enabled: true,
        comment: name,
        priceClass: 'PriceClass_200',
        aliases: [laneFqdn],
        // WAF is deferred to P9
        origins: [
          {
            id: 'alb',
            domainName: laneFqdn,
            vpcOriginConfig: {
              vpcOriginId: this.vpcOrigin.attrId,
            },
          },
          {
            id: 's3',
            domainName: props.s3BucketDomainName,
            s3OriginConfig: {
              originAccessIdentity: '',
            },
            originAccessControlId: props.oacId,
          },
        ],
        defaultCacheBehavior: {
          allowedMethods: ['DELETE', 'GET', 'HEAD', 'OPTIONS', 'PATCH', 'POST', 'PUT'],
          cachedMethods: ['GET', 'HEAD'],
          targetOriginId: 'alb',
          cachePolicyId: '4135ea2d-6df8-44a3-9df3-4b5a84be39ad', // Managed-CachingDisabled
          originRequestPolicyId: 'b689b0a8-53d0-40ab-baf2-68738e2966ac', // Managed-AllViewerExceptHostHeader
          viewerProtocolPolicy: 'redirect-to-https',
          compress: true,
        },
        cacheBehaviors: [
          {
            pathPattern: '/assets/*',
            allowedMethods: ['GET', 'HEAD', 'OPTIONS'],
            cachedMethods: ['GET', 'HEAD'],
            targetOriginId: 's3',
            cachePolicyId: staticCachePolicy.ref,
            viewerProtocolPolicy: 'redirect-to-https',
            compress: true,
          },
        ],
        restrictions: {
          geoRestriction: {
            restrictionType: 'whitelist',
            locations: ['JP'],
          },
        },
        logging: {
          bucket: props.logBucketDomainName,
          prefix: `cloudfront/${props.lane}/`,
          includeCookies: false,
        },
        viewerCertificate: {
          acmCertificateArn: props.acmCloudfrontCertArn,
          sslSupportMethod: 'sni-only',
          minimumProtocolVersion: 'TLSv1.2_2021',
        },
      },
      tags: [{ key: 'Name', value: name }],
    });

    // --------------------------------------------------------------------------------
    // S3 Bucket Policy: allow CloudFront OAC GetObject
    // --------------------------------------------------------------------------------

    const bucketArn = `arn:aws:s3:::${props.s3BucketId}`;

    new s3.CfnBucketPolicy(this, 'S3OacPolicy', {
      bucket: props.s3BucketId,
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
          {
            Sid: 'AllowCloudFrontServicePrincipal',
            Effect: 'Allow',
            Principal: { Service: 'cloudfront.amazonaws.com' },
            Action: 's3:GetObject',
            Resource: `${bucketArn}/*`,
            Condition: {
              StringEquals: {
                'AWS:SourceArn': Fn.join('', [
                  'arn:aws:cloudfront::',
                  props.accountId,
                  ':distribution/',
                  this.distribution.ref,
                ]),
              },
            },
          },
        ],
      },
    });

    // --------------------------------------------------------------------------------
    // Security Group Rule: ALB ingress from CloudFront VPC Origin
    // CloudFront VPC Origin creates a managed SG "CloudFront-VPCOrigins-Service-SG".
    // In Terraform, this is looked up via data source. In CDK, we cannot do SG lookup
    // at synth time without a custom resource.
    // The VPC Origin service automatically manages SG rules for connectivity.
    // If explicit ingress is needed, add a Custom Resource to look up the managed SG
    // or configure the ALB SG to allow HTTPS from the VPC CIDR.
    // --------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------
    // Route53 A Record: lane subdomain -> CloudFront
    // --------------------------------------------------------------------------------

    new route53.CfnRecordSet(this, 'DnsAlias', {
      hostedZoneId: props.hostedZoneId,
      name: laneFqdn,
      type: 'A',
      aliasTarget: {
        dnsName: this.distribution.attrDomainName,
        hostedZoneId: 'Z2FDTNDATAQYW2', // CloudFront hosted zone ID (global constant)
        evaluateTargetHealth: false,
      },
    });
  }
}
