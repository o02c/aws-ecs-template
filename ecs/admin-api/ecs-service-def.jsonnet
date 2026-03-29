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
      containerName: 'app',
      containerPort: 80,
      targetGroupArn: "{{ tfstate `module.lb['admin'].aws_lb_target_group.this.arn` }}",
    },
  ],
  networkConfiguration: {
    awsvpcConfiguration: {
      assignPublicIp: 'DISABLED',
      securityGroups: [
        "{{ tfstate `module.network.aws_security_group.this['ecs'].id` }}",
      ],
      subnets: [
        "{{ tfstate `module.network.aws_subnet.private['ap-northeast-1a'].id` }}",
        "{{ tfstate `module.network.aws_subnet.private['ap-northeast-1c'].id` }}",
      ],
    },
  },
  platformVersion: 'LATEST',
}
