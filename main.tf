terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- Data Sources ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

# --- ECR Registry ---
resource "aws_ecr_repository" "litellm_repo" {
  name         = "litellm-lab-repo"
  force_delete = true
}

# --- IAM Roles ---
resource "aws_iam_role" "ecs_execution_role" {
  name = "litellm_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_execution_attach" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "litellm_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}

# THE CRITICAL FIX: Marketplace Permissions Added Here
resource "aws_iam_policy" "bedrock_access" {
  name = "LiteLLMBedrockAccess"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "aws-marketplace:ViewSubscriptions",
          "aws-marketplace:Subscribe",
          "aws-marketplace:Unsubscribe"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "task_bedrock_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.bedrock_access.arn
}

# --- Security Group ---
resource "aws_security_group" "litellm_sg" {
  name   = "litellm-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port = 4000
    to_port   = 4000
    protocol  = "tcp"
    cidr_blocks = [
      "${chomp(data.http.myip.response_body)}/32"
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- ECS Service ---
resource "aws_ecs_cluster" "main" { name = "litellm-cluster" }

resource "aws_cloudwatch_log_group" "litellm_logs" {
  name              = "/ecs/litellm"
  retention_in_days = 1
}

resource "aws_ecs_task_definition" "litellm_task" {
  family                   = "litellm-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "litellm"
    image     = "${aws_ecr_repository.litellm_repo.repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 4000, hostPort = 4000 }]
    logConfiguration = {
      logDriver = "awslogs"
      options = { "awslogs-group" = "/ecs/litellm", "awslogs-region" = "us-east-1", "awslogs-stream-prefix" = "ecs" }
    }
  }])
}

resource "aws_ecs_service" "litellm_service" {
  name            = "litellm-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.litellm_task.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 100
  }

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.litellm_sg.id]
    assign_public_ip = true
  }
  force_new_deployment = true
}

output "ecr_repo_url" { value = aws_ecr_repository.litellm_repo.repository_url }
