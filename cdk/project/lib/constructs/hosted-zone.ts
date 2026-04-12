import { Construct } from 'constructs';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';

// --------------------------------------------------------------------------------
// Props
// --------------------------------------------------------------------------------

export interface HostedZoneProps {
  projectName: string;
  environment: string;
  domainName: string;
  deployMode: 'cdk-deploy' | 'template-only';
}

export class HostedZone extends Construct {
  public readonly zone: route53.CfnHostedZone;
  public readonly regionalCertificate: acm.CfnCertificate;

  constructor(scope: Construct, id: string, props: HostedZoneProps) {
    super(scope, id);

    const prefix = `${props.projectName}-${props.environment}`;

    // --------------------------------------------------------------------------------
    // Route53 Public Hosted Zone
    // --------------------------------------------------------------------------------

    this.zone = new route53.CfnHostedZone(this, 'HostedZone', {
      name: props.domainName,
      hostedZoneTags: [{ key: 'Name', value: `${prefix}-${props.domainName}` }],
    });

    // --------------------------------------------------------------------------------
    // ACM Certificate (Regional - ap-northeast-1, for ALB)
    // --------------------------------------------------------------------------------

    this.regionalCertificate = new acm.CfnCertificate(this, 'RegionalCert', {
      domainName: props.domainName,
      subjectAlternativeNames: [`*.${props.domainName}`],
      validationMethod: 'DNS',
      domainValidationOptions: [
        {
          domainName: props.domainName,
          hostedZoneId: this.zone.ref,
        },
        {
          domainName: `*.${props.domainName}`,
          hostedZoneId: this.zone.ref,
        },
      ],
      tags: [{ key: 'Name', value: `${prefix}-regional` }],
    });

    // Note: us-east-1 ACM Certificate for CloudFront is deferred to #16
    // In template-only mode, the ARN will be received from config
  }
}
