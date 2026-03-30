{
  containerDefinitions: [
    {
      name: 'app',
      image: "{{ tfstate `module.app.aws_ecr_repository.this['user-api'].repository_url` }}:v20260330072940",
      portMappings: [
        {
          containerPort: 80,
          protocol: 'tcp',
        },
      ],
      essential: true,
      logConfiguration: {
        logDriver: 'awslogs',
        options: {
          'awslogs-group': "{{ tfstate `module.app.aws_cloudwatch_log_group.this['user-api'].name` }}",
          'awslogs-region': 'ap-northeast-1',
          'awslogs-stream-prefix': 'ecs',
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
  cpu: '256',
  memory: '512',
  executionRoleArn: "{{ tfstate `module.app.aws_iam_role.task_execution.arn` }}",
  taskRoleArn: "{{ tfstate `module.app.aws_iam_role.task['user-api'].arn` }}",
  family: 'user-api',
  networkMode: 'awsvpc',
  requiresCompatibilities: ['FARGATE'],
}
