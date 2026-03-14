local tfstate(key) = '{{ tfstate `%s` }}' % key;

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
      targetGroupArn: tfstate('module.lb["admin"].target_group_arn'),
    },
  ],
  networkConfiguration: {
    awsvpcConfiguration: {
      assignPublicIp: 'DISABLED',
      securityGroups: [
        tfstate('module.network.security_group_ids["ecs"]'),
      ],
      subnets: std.objectValues(
        std.parseJson(tfstate('module.network.private_subnet_ids'))
      ),
    },
  },
  platformVersion: 'LATEST',
}
