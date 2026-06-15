# ============================================================
#  ex02 — 테라폼으로 배포하기
#  ex01에서 손으로 클릭하던 모든 것을 이 파일 한 벌이 대신합니다.
#  terraform apply   → 전부 생성
#  terraform destroy → 전부 삭제
# ============================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---- 현재 계정 / 기본 네트워크 정보 가져오기 ----
data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  ecr_base    = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  basic_image = "${local.ecr_base}/basic-server:${var.image_tag}"
  auth_image  = "${local.ecr_base}/auth-server:${var.image_tag}"
}

# ============================================================
#  IAM — Task 실행 역할 (ECR pull + 로그 권한)
# ============================================================
resource "aws_iam_role" "execution" {
  name = "${var.project}-ecs-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ============================================================
#  ECS 클러스터 + CloudWatch 로그 그룹
# ============================================================
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"
}

resource "aws_cloudwatch_log_group" "basic" {
  name              = "/ecs/${var.project}-basic"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "auth" {
  name              = "/ecs/${var.project}-auth"
  retention_in_days = 7
}

# ============================================================
#  보안 그룹 — ALB(80 공개) → 서비스(8080, ALB에서만)
# ============================================================
resource "aws_security_group" "alb" {
  name   = "${var.project}-alb-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "service" {
  name   = "${var.project}-service-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ============================================================
#  ALB + 대상 그룹 2개 + 리스너(경로 라우팅)
# ============================================================
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "basic" {
  name        = "${var.project}-basic-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip" # Fargate는 ip 타겟

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

resource "aws_lb_target_group" "auth" {
  name        = "${var.project}-auth-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

# 기본(default) 트래픽 → basic-server
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.basic.arn
  }
}

# /auth* 경로 → auth-server
resource "aws_lb_listener_rule" "auth" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth.arn
  }
  condition {
    path_pattern {
      values = ["/auth", "/auth/*"]
    }
  }
}

# ============================================================
#  작업 정의 (Task Definition) 2개
# ============================================================
resource "aws_ecs_task_definition" "basic" {
  family                   = "${var.project}-basic"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([{
    name      = "basic-server"
    image     = local.basic_image
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.basic.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "auth" {
  family                   = "${var.project}-auth"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([{
    name      = "auth-server"
    image     = local.auth_image
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.auth.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ============================================================
#  ECS 서비스 2개  (기본서버 2개, 인증서버 1개)
# ============================================================
resource "aws_ecs_service" "basic" {
  name            = "${var.project}-basic"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.basic.arn
  desired_count   = var.basic_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.basic.arn
    container_name   = "basic-server"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_ecs_service" "auth" {
  name            = "${var.project}-auth"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.auth.arn
  desired_count   = var.auth_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.auth.arn
    container_name   = "auth-server"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener_rule.auth]
}

# ============================================================
#  오토스케일링 — 기본서버 CPU 70% 기준 1~10개
# ============================================================
resource "aws_appautoscaling_target" "basic" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.basic.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "basic_cpu" {
  name               = "${var.project}-basic-cpu70"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.basic.resource_id
  scalable_dimension = aws_appautoscaling_target.basic.scalable_dimension
  service_namespace  = aws_appautoscaling_target.basic.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
