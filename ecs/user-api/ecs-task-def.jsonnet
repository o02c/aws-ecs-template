local tfstate(key) = '{{ tfstate `%s` }}' % key;

{
  containerDefinitions: [
    {
      name: 'app',
      image: tfstate('module.app.ecr_repository_urls["user-api"]') + ':latest',
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
          'awslogs-group': tfstate('module.app.log_group_names["user-api"]'),
          'awslogs-region': 'ap-northeast-1',
          'awslogs-stream-prefix': 'ecs',
        },
      },
      environment: [],
      secrets: [],
    },
  ],
  cpu: '256',
  memory: '512',
  executionRoleArn: tfstate('module.app.task_execution_role_arn'),
  taskRoleArn: tfstate('module.app.task_role_arns["user-api"]'),
  family: 'user-api',
  networkMode: 'awsvpc',
  requiresCompatibilities: ['FARGATE'],
}
