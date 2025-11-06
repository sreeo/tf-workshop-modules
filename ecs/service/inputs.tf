variable "cluster_arn" {
  description = "The ARN of the ECS Cluster"
  type        = string
}

variable "dns_zone_name" {
  description = "DNS Zone Name"
  type        = string
}

variable "dns_prefix" {
  description = "DNS Record Prefix"
  type        = string
}

variable "env" {
  description = "Deployment Environment"
  type        = string
}

variable "service_name" {
  description = "Name of the ECS Service"
  type        = string
}

variable "service_port" {
  description = "Port of the ECS Service"
  type        = number
}

variable "service_desired_count" {
  description = "Desired replica count of the ECS Service"
  type        = number
  default     = null
}

variable "enable_dns" {
  description = "Enable Route53 DNS and ACM certificate creation. Set to false to skip DNS (use ALB DNS directly)"
  type        = bool
  default     = true
}

variable "manage_route53_records" {
  description = "Whether to create Route53 records via Terraform. Set to false for cross-account DNS (manual record creation in different account)"
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "Existing ACM certificate ARN to use instead of creating a new one. Useful for cross-account setups."
  type        = string
  default     = null
}

variable "use_https" {
  description = "Whether to use HTTPS on the ALB listener. Set to false to keep HTTP while certificate is being validated."
  type        = bool
  default     = true
}
