{
  volumes: [
    { name: 'app-tmp' },
    { name: 'nginx-cache' },
    { name: 'nginx-run' },
    { name: 'nginx-tmp' },
  ],
  containerDefinitions: [
    {
      name: 'log_router',
      image: "{{ tfstate `output.ecr_public_cache_base_uri` }}/aws-observability/aws-for-fluent-bit:init-latest",
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
          'awslogs-group': "{{ tfstate `module.app.aws_cloudwatch_log_group.fluent_bit[0].name` }}",
          'awslogs-region': 'ap-northeast-1',
          'awslogs-stream-prefix': 'admin-api',
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
      image: "{{ tfstate `module.app.aws_ecr_repository.this['admin-api'].repository_url` }}:{{ env `IMAGE_TAG` `latest` }}",
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
        command: ['CMD-SHELL', "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8080/admin/api/health')\""],
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
          name: 'DJANGO_DEBUG',
          value: 'true',
        },
        {
          name: 'ALLOWED_HOSTS',
          value: "localhost,127.0.0.1,{{ tfstate `output.domain_name` }}",
        },
        {
          name: 'S3_BUCKET_NAME',
          value: "{{ tfstate `module.storage['admin'].aws_s3_bucket.this.id` }}",
        },
        {
          name: 'APP_RESOURCES_BUCKET',
          value: "{{ tfstate `module.app.aws_s3_bucket.app_resources.id` }}",
        },
        {
          name: 'LANE',
          value: 'admin',
        },
        {
          name: 'CLOUDFRONT_DOMAIN',
          value: "{{ tfstate `output.domain_name` }}",
        },
        {
          name: 'CLOUDFRONT_KEY_PAIR_ID',
          value: '',
        },
        {
          name: 'CLOUDFRONT_SIGNING_KEY_SECRET_ARN',
          value: '',
        },
        {
          name: 'SES_FROM_ADDRESS',
          value: "{{ tfstate `output.ses_sender_address` }}",
        },
        {
          name: 'SES_ALLOWED_RECIPIENTS',
          value: "{{ tfstate `output.ses_verified_recipients_csv` }}",
        },
        {
          # VPCE `com.amazonaws.<region>.email` advertises `email.<region>.api.aws`
          # (SESv2 endpoint). Boto3 default `email.<region>.amazonaws.com` is not
          # reachable from the private ECS SG; pin to the VPCE-served hostname.
          name: 'SES_ENDPOINT_URL',
          value: 'https://email.ap-northeast-1.api.aws',
        },
        # Aurora IAM auth. DB_USER matches db_config.iam_username; task role's
        # rds_iam_auth_policy allows rds-db:connect on this dbuser only.
        {
          name: 'DB_HOST',
          value: "{{ tfstate `module.db.aws_rds_cluster.this.endpoint` }}",
        },
        {
          name: 'DB_PORT',
          value: '5432',
        },
        {
          name: 'DB_NAME',
          value: "{{ tfstate `module.db.aws_rds_cluster.this.database_name` }}",
        },
        {
          name: 'DB_USER',
          value: 'app',
        },
      ],
      secrets: [
        {
          name: 'DJANGO_SECRET_KEY',
          valueFrom: "{{ tfstate `module.app.aws_ssm_parameter.django_secret_key['admin-api'].arn` }}",
        },
      ],
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
