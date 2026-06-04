{
  # All containers run read-only root FS as non-root users; every writable path
  # is an in-memory tmpfs (declared per-container in linuxParameters) rather than
  # an ephemeral task volume, because Fargate task volumes mount root:root and a
  # non-root user can't write to them (tmpfs mode=1777 sidesteps that).
  containerDefinitions: [
    // FireLens log router.
    // readonlyRootFilesystem ON — the init image falls back to /tmp/init when
    // /init is read-only (canWriteToDir check in fluent_bit_init_process), so an
    // in-memory tmpfs at /tmp is the only writable surface it needs. No disk
    // buffering: outputs go straight to Firehose, and /fluent-bit/etc/fluent-bit.conf
    // (FireLens-generated) is only read/@INCLUDE'd, never written.
    {
      name: 'log_router',
      image: "{{ tfstate `output.ecr_public_cache_base_uri` }}/aws-observability/aws-for-fluent-bit:init-latest",
      # Non-root: the init image supports non-root mode (aws-for-fluent-bit #955) by
      # falling back to /tmp/init. tmpfs below is mode=1777 so uid 10001 can write it.
      user: '10001',
      readonlyRootFilesystem: true,
      essential: true,
      stopTimeout: 30,
      firelensConfiguration: {
        type: 'fluentbit',
      },
      environment: [
        { name: 'aws_fluent_bit_init_s3_1', value: "{{ tfstate `output.fluent_bit_config_s3_arn` }}" },
        # Optional opt-in parsers (python_json / nginx / nginx_json). Registered
        # but unused unless extra.conf references them — see files/fluent-bit-parsers.conf.
        { name: 'aws_fluent_bit_init_s3_2', value: "{{ tfstate `output.fluent_bit_parsers_s3_arn` }}" },
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
      # In-memory scratch for the init process's /tmp/init fallback (read-only root FS).
      linuxParameters: {
        tmpfs: [
          { containerPath: '/tmp', size: 64, mountOptions: ['noexec', 'nosuid', 'nodev', 'mode=1777'] },
        ],
      },
      memoryReservation: 64,
    },
    {
      name: 'nginx',
      image: "{{ tfstate `module.app.aws_ecr_repository.nginx.repository_url` }}:{{ env `NGINX_IMAGE_TAG` `latest` }}",
      # nginx-unprivileged image runs as uid 101 by default (no `user` override needed).
      readonlyRootFilesystem: true,
      stopTimeout: 30,
      portMappings: [
        {
          containerPort: 8081,
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
          Name: 'kinesis_firehose',
          region: 'ap-northeast-1',
          delivery_stream: "{{ tfstate `output.firehose_stream_names['ecs-logs-nginx']` }}",
        },
      },
      # Writable scratch for uid 101: pid (/tmp/nginx.pid) + proxy/client temp dirs
      # (/var/cache/nginx/*). mode=1777 so the non-root nginx user can write.
      linuxParameters: {
        tmpfs: [
          { containerPath: '/var/cache/nginx', size: 64, mountOptions: ['noexec', 'nosuid', 'nodev', 'mode=1777'] },
          { containerPath: '/tmp', size: 16, mountOptions: ['noexec', 'nosuid', 'nodev', 'mode=1777'] },
        ],
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
      # Writable scratch for uid 10001 (gunicorn worker tmp dir + HOME). mode=1777
      # so the non-root app user can write; Fargate task volumes would be root-owned.
      linuxParameters: {
        tmpfs: [
          { containerPath: '/tmp', size: 64, mountOptions: ['nosuid', 'nodev', 'mode=1777'] },
        ],
      },
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
          delivery_stream: "{{ tfstate `output.firehose_stream_names['ecs-logs-app']` }}",
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
