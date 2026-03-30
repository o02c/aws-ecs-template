{
  deploymentConfiguration: {
    deploymentCircuitBreaker: {
      enable: true,
      rollback: true,
    },
    maximumPercent: 200,
    minimumHealthyPercent: 100,
  },
  desiredCount: 1,
  enableExecuteCommand: true,
  launchType: 'FARGATE',
  loadBalancers: [
    {
      containerName: 'nginx',
      containerPort: 80,
      targetGroupArn: "{{ tfstate `output.target_group_arns['user']` }}",
    },
  ],
  networkConfiguration: {
    awsvpcConfiguration: {
      assignPublicIp: 'DISABLED',
      securityGroups: [
        "{{ tfstate `output.ecs_security_group_id` }}",
      ],
      subnets: [
        "{{ tfstate `output.private_subnet_ids['ap-northeast-1a']` }}",
        "{{ tfstate `output.private_subnet_ids['ap-northeast-1c']` }}",
      ],
    },
  },
  platformVersion: 'LATEST',
}
