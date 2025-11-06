# Locals
locals {
  lb_port = var.enable_dns && var.use_https ? 443 : 80
}

# DATA
data "aws_vpc" "main" {
  filter {
    name   = "tag:Env"
    values = [var.env]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    Type = "private"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    Type = "public"
  }
}

data "aws_route53_zone" "main" {
  count = var.enable_dns && var.manage_route53_records ? 1 : 0
  name  = "${var.dns_zone_name}."
}

# ECR REPO
resource "aws_ecr_repository" "service_repo" {
  count = var.env == "prd" ? 1 : 0
  name  = var.service_name
}

# INITIAL ECS TASK
resource "aws_ecs_task_definition" "initial" {
  family                   = "${var.env}-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_service_task_role.arn

  container_definitions = jsonencode([{
    name  = var.service_name
    image = "nginx"
    portMappings = [{
      containerPort = var.service_port
      hostPort      = var.service_port
    }]
  }])
}

# AWS SECURITY GROUP
resource "aws_security_group" "lb" {
  name        = "${var.env}-${var.service_name}-lb-security-group"
  description = "Internal traffic to ECS Service"
  vpc_id      = data.aws_vpc.main.id

  tags = {
    Name    = "${var.env}-${var.service_name}-lb-sg"
    Env     = var.env
    Service = var.service_name
  }

  ingress {
    protocol    = "tcp"
    from_port   = local.lb_port
    to_port     = local.lb_port
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "task_sg" {
  name   = "${var.env}-${var.service_name}-security-group"
  vpc_id = data.aws_vpc.main.id

  tags = {
    Name    = "${var.env}-${var.service_name}-task-sg"
    Env     = var.env
    Service = var.service_name
  }

  ingress {
    protocol        = "tcp"
    from_port       = var.service_port
    to_port         = var.service_port
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS SERVICE
resource "aws_ecs_service" "service" {
  health_check_grace_period_seconds = 60
  name                = "${var.env}-${var.service_name}-ecs-service"
  cluster             = var.cluster_arn
  task_definition     = aws_ecs_task_definition.initial.arn
  launch_type         = "FARGATE"
  scheduling_strategy = "REPLICA"
  desired_count       = var.service_desired_count != null ? var.service_desired_count : (var.env == "prd" ? 2 : 1)

  tags = {
    Name    = "${var.env}-${var.service_name}-ecs-service"
    Env     = var.env
    Service = var.service_name
  }

  deployment_controller {
    type = "ECS"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.service.id
    container_name   = var.service_name
    container_port   = var.service_port
  }

  network_configuration {
    subnets         = data.aws_subnets.private.ids
    security_groups = [aws_security_group.task_sg.id]
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb.main, aws_lb_listener.service]
}

# Task Role Permissions
resource "aws_iam_role" "ecs_service_task_role" {
  name = "${var.service_name}-task-role"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "task_role_policy_attachment" {
  role       = aws_iam_role.ecs_service_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_policy" "task_ecr_access" {
  name        = "${var.service_name}-task-ecr-access"
  description = "Allow ECS Task to access ECR"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowECR",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "task_ecr_policy_attachment" {
  role       = aws_iam_role.ecs_service_task_role.name
  policy_arn = aws_iam_policy.task_ecr_access.arn
}

# LB
resource "aws_lb" "main" {
  name            = "${var.env}-${var.service_name}-lb"
  subnets         = data.aws_subnets.public.ids
  idle_timeout = 300
  security_groups = [aws_security_group.lb.id]
}

resource "aws_lb_target_group" "service" {
  name        = "${var.env}-${var.service_name}-tg"
  port        = var.service_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/health"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 10
  }

  tags = {
    Name    = "${var.env}-${var.service_name}-tg"
    Env     = var.env
    Service = var.service_name
  }
}

# ALB Listener - HTTPS when enabled and certificate available, otherwise HTTP
resource "aws_lb_listener" "service" {
  load_balancer_arn = aws_lb.main.id
  port              = var.enable_dns && var.use_https ? local.lb_port : 80
  protocol          = var.enable_dns && var.use_https ? "HTTPS" : "HTTP"
  ssl_policy        = var.enable_dns && var.use_https ? "ELBSecurityPolicy-2016-08" : null
  certificate_arn   = var.enable_dns && var.use_https ? (var.certificate_arn != null ? var.certificate_arn : aws_acm_certificate.service[0].arn) : null

  default_action {
    target_group_arn = aws_lb_target_group.service.id
    type             = "forward"
  }
}

# ACM Certificate - only create if enable_dns is true AND no existing certificate is provided
resource "aws_acm_certificate" "service" {
  count             = var.enable_dns && var.certificate_arn == null ? 1 : 0
  domain_name       = "${var.dns_prefix}.${var.dns_zone_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Route53 validation record - only if managing Route53 and creating certificate
resource "aws_route53_record" "cert_validation" {
  count           = var.enable_dns && var.manage_route53_records && var.certificate_arn == null ? 1 : 0
  allow_overwrite = true
  name            = tolist(aws_acm_certificate.service[0].domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.service[0].domain_validation_options)[0].resource_record_value]
  type            = tolist(aws_acm_certificate.service[0].domain_validation_options)[0].resource_record_type
  zone_id         = data.aws_route53_zone.main[0].id
  ttl             = 60
}

# Certificate validation - only if managing Route53 and creating certificate
resource "aws_acm_certificate_validation" "cert" {
  count                   = var.enable_dns && var.manage_route53_records && var.certificate_arn == null ? 1 : 0
  certificate_arn         = aws_acm_certificate.service[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[0].fqdn]
}

# Route53 A record pointing to ALB - only if managing Route53
resource "aws_route53_record" "service" {
  count   = var.enable_dns && var.manage_route53_records ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "${var.dns_prefix}.${var.dns_zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}