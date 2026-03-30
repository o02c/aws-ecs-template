{
  containerDefinitions: [
    // FireLens log router (Fluent Bit)
    {
      name: 'log_router',
      image: "{{ tfstate `module.app.aws_ecr_repository.fluent_bit.repository_url` }}:{{ env `FLUENTBIT_IMAGE_TAG` `latest` }}",
      essential: true,
      firelensConfiguration: {
        type: 'fluentbit',
        options: {
          'config-file-type': 'file',
          'config-file-value': '/fluent-bit/etc/extra.conf',
        },
      },
      environment: [
        { name: 'AWS_REGION', value: 'ap-northeast-1' },
        { name: 'LOG_GROUP', value: "{{ tfstate `module.app.aws_cloudwatch_log_group.this['user-api'].name` }}" },
        { name: 'FIREHOSE_STREAM', value: "{{ tfstate `module.app.aws_kinesis_firehose_delivery_stream.audit_logs.name` }}" },
      ],
      logConfiguration: {
        logDriver: 'awslogs',
        options: {
          'awslogs-group': "{{ tfstate `module.app.aws_cloudwatch_log_group.this['user-api'].name` }}",
          'awslogs-region': 'ap-northeast-1',
          'awslogs-stream-prefix': 'firelens',
        },
      },
      memoryReservation: 64,
    },
    // nginx reverse proxy
    {
      name: 'nginx',
      image: "{{ tfstate `module.app.aws_ecr_repository.nginx.repository_url` }}:{{ env `NGINX_IMAGE_TAG` `latest` }}",
      portMappings: [
        {
          containerPort: 80,
          protocol: 'tcp',
        },
      ],
      essential: true,
      dependsOn: [
        { containerName: 'app', condition: 'HEALTHY' },
        { containerName: 'log_router', condition: 'START' },
      ],
      logConfiguration: {
        logDriver: 'awsfirelens',
        options: {
          Name: 'cloudwatch_logs',
          region: 'ap-northeast-1',
          log_group_name: "{{ tfstate `module.app.aws_cloudwatch_log_group.this['user-api'].name` }}",
          log_stream_prefix: 'nginx/',
          auto_create_group: 'false',
        },
      },
      memoryReservation: 64,
    },
    // Application container
    {
      name: 'app',
      image: "{{ tfstate `module.app.aws_ecr_repository.this['user-api'].repository_url` }}:{{ env `IMAGE_TAG` `latest` }}",
      portMappings: [
        {
          containerPort: 8080,
          protocol: 'tcp',
        },
      ],
      essential: true,
      dependsOn: [
        { containerName: 'log_router', condition: 'START' },
      ],
      healthCheck: {
        command: ['CMD-SHELL', "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8080/health')\""],
        interval: 15,
        timeout: 5,
        retries: 3,
        startPeriod: 30,
      },
      logConfiguration: {
        logDriver: 'awsfirelens',
        options: {
          Name: 'cloudwatch_logs',
          region: 'ap-northeast-1',
          log_group_name: "{{ tfstate `module.app.aws_cloudwatch_log_group.this['user-api'].name` }}",
          log_stream_prefix: 'app/',
          auto_create_group: 'false',
        },
      },
      environment: [
        {
          name: 'S3_BUCKET_NAME',
          value: "{{ tfstate `module.storage['user'].aws_s3_bucket.this.id` }}",
        },
        {
          name: 'CLOUDFRONT_DOMAIN',
          value: 'user.o2c.click',
        },
        // Configure when CloudFront signed URLs are enabled
        {
          name: 'CLOUDFRONT_KEY_PAIR_ID',
          value: '',
        },
        {
          name: 'CLOUDFRONT_SIGNING_KEY_SECRET_ARN',
          value: '',
        },
      ],
      secrets: [],
    },
  ],
  cpu: '512',
  memory: '1024',
  executionRoleArn: "{{ tfstate `module.app.aws_iam_role.task_execution.arn` }}",
  taskRoleArn: "{{ tfstate `module.app.aws_iam_role.task['user-api'].arn` }}",
  family: 'user-api',
  networkMode: 'awsvpc',
  requiresCompatibilities: ['FARGATE'],
}
