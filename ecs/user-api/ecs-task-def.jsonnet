{
  volumes: [
    { name: 'app-tmp' },
    { name: 'nginx-cache' },
    { name: 'nginx-run' },
    { name: 'nginx-tmp' },
  ],
  containerDefinitions: [
    // FireLens log router.
    // NOTE: readonlyRootFilesystem OFF — init process writes to /fluent-bit/etc.
    // logConfiguration uses awslogs (fluent-bit can't route its own output via
    // FireLens). Short retention, trivial volume — diagnostic only.
    {
      name: 'log_router',
      image: "{{ tfstate `output.fluent_bit_init_image` }}",
      essential: true,
      stopTimeout: 30,
      firelensConfiguration: {
        type: 'fluentbit',
      },
      environment: [
        { name: 'aws_fluent_bit_init_s3_1', value: "{{ tfstate `output.fluent_bit_config_s3_arn` }}" },
        { name: 'aws_fluent_bit_init_file_1', value: '/fluent-bit/parsers/parsers.conf' },
        { name: 'AUDIT_STREAM', value: "{{ tfstate `output.firehose_stream_names['audit']` }}" },
      ],
      logConfiguration: {
        logDriver: 'awslogs',
        options: {
          'awslogs-group': "{{ tfstate `module.app.aws_cloudwatch_log_group.fluent_bit.name` }}",
          'awslogs-region': 'ap-northeast-1',
          'awslogs-stream-prefix': 'user-api',
        },
      },
      memoryReservation: 64,
    },
    {
      name: 'nginx',
      image: "{{ tfstate `module.app.aws_ecr_repository.nginx.repository_url` }}:{{ env `NGINX_IMAGE_TAG` `latest` }}",
      readonlyRootFilesystem: true,
      stopTimeout: 30,
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
      mountPoints: [
        { sourceVolume: 'nginx-cache', containerPath: '/var/cache/nginx', readOnly: false },
        { sourceVolume: 'nginx-run', containerPath: '/var/run', readOnly: false },
        { sourceVolume: 'nginx-tmp', containerPath: '/tmp', readOnly: false },
      ],
      logConfiguration: {
        logDriver: 'awsfirelens',
        options: {
          Name: 'kinesis_firehose',
          region: 'ap-northeast-1',
          delivery_stream: "{{ tfstate `output.firehose_stream_names['ecs-logs']` }}",
        },
      },
      memoryReservation: 64,
    },
    {
      name: 'app',
      image: "{{ tfstate `module.app.aws_ecr_repository.this['user-api'].repository_url` }}:{{ env `IMAGE_TAG` `latest` }}",
      readonlyRootFilesystem: true,
      stopTimeout: 30,
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
      mountPoints: [
        { sourceVolume: 'app-tmp', containerPath: '/tmp', readOnly: false },
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
          Name: 'kinesis_firehose',
          region: 'ap-northeast-1',
          delivery_stream: "{{ tfstate `output.firehose_stream_names['ecs-logs']` }}",
        },
      },
      environment: [
        {
          name: 'PYTHONDONTWRITEBYTECODE',
          value: '1',
        },
        {
          name: 'ALLOWED_HOSTS',
          value: "localhost,127.0.0.1,{{ tfstate `output.lane_domains['user']` }}",
        },
        {
          name: 'S3_BUCKET_NAME',
          value: "{{ tfstate `module.storage['user'].aws_s3_bucket.this.id` }}",
        },
        {
          name: 'CLOUDFRONT_DOMAIN',
          value: "{{ tfstate `output.lane_domains['user']` }}",
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
      secrets: [
        {
          name: 'DJANGO_SECRET_KEY',
          valueFrom: "{{ tfstate `module.app.aws_ssm_parameter.django_secret_key['user-api'].arn` }}",
        },
      ],
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
