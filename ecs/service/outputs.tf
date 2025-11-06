output "task_execution_role_arn" {
  description = "The ARN of the ECS Task Execution Role"
  value       = aws_iam_role.ecs_service_task_role.arn
}

output "service_name" {
  description = "Name of the ECS Service (for autoscaling configuration)"
  value       = aws_ecs_service.service.name
}

output "cluster_name" {
  description = "Name of the ECS Cluster (for autoscaling configuration)"
  value       = split("/", var.cluster_arn)[1]
}