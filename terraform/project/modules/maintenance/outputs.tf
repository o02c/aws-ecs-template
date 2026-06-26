output "state_machine_arn" {
  description = "Maintenance toggle state machine ARN (manual flip: aws stepfunctions start-execution --state-machine-arn <arn> --input '{\"value\":\"on\"}')"
  value       = aws_sfn_state_machine.toggle.arn
}
