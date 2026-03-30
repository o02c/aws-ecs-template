{
  containerDefinitions: [
    // FireLens log router (init-latest via ECR pull-through cache)
    // ref: https://github.com/aws/aws-for-fluent-bit/blob/mainline/use_cases/init-process-for-fluent-bit/README.md
    // ref: https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html
    {
      name: 'log_router',
      image: "{{ tfstate `output.fluent_bit_init_image` }}",
      essential: true,
      firelensConfiguration: {
        type: 'fluentbit',
      },
      environment: [
        { name: 'aws_fluent_bit_init_s3_1', value: "{{ tfstate `output.fluent_bit_config_s3_arn` }}" },
        { name: 'aws_fluent_bit_init_file_1', value: '/fluent-bit/parsers/parsers.conf' },
        { name: 'LOG_GROUP', value: "{{ tfstate `module.app.aws_cloudwatch_log_group.this['admin-api'].name` }}" },
        { name: 'FIREHOSE_STREAM', value: "{{ tfstate `module.app.aws_kinesis_firehose_delivery_stream.audit_logs.name` }}" },
      ],
      logConfiguration: {
        logDriver: 'awslogs',
        options: {
          'awslogs-group': "{{ tfstate `module.app.aws_cloudwatch_log_group.this['admin-api'].name` }}",
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
          log_group_name: "{{ tfstate `module.app.aws_cloudwatch_log_group.this['admin-api'].name` }}",
          log_stream_prefix: 'nginx/',
          auto_create_group: 'false',
        },
      },
      memoryReservation: 64,
    },
    // Application container
    {
      name: 'app',
      image: "{{ tfstate `module.app.aws_ecr_repository.this['admin-api'].repository_url` }}:{{ env `IMAGE_TAG` `latest` }}",
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
          log_group_name: "{{ tfstate `module.app.aws_cloudwatch_log_group.this['admin-api'].name` }}",
          log_stream_prefix: 'app/',
          auto_create_group: 'false',
        },
      },
      environment: [
        {
          name: 'S3_BUCKET_NAME',
          value: "{{ tfstate `module.storage['admin'].aws_s3_bucket.this.id` }}",
        },
        {
          name: 'CLOUDFRONT_DOMAIN',
          value: 'admin.o2c.click',
        },
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
  taskRoleArn: "{{ tfstate `module.app.aws_iam_role.task['admin-api'].arn` }}",
  family: 'admin-api',
  networkMode: 'awsvpc',
  requiresCompatibilities: ['FARGATE'],
}
