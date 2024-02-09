locals {
  tags = {
    backstage = "v0.1.0"
  }
}


resource "aws_ecs_cluster" "backstage_fargate_cluster" {
  name = "backstage"

  tags = local.tags
}

resource "aws_ecr_repository" "backstage_ecr" {
  name = "backstage_ecr"

  tags = local.tags
}

output "ecr_url" {
  value = aws_ecr_repository.backstage_ecr.repository_url
}

# resource "aws_iam_role" "task_role" {
#   name = "backstage_task_role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Sid    = ""
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       },
#     ]
#   })
#   tags = local.tags
# }


data "aws_iam_policy" "ecsTaskExecutionRolePolicy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# Attach managed policy to IAM role
resource "aws_iam_role_policy_attachment" "task_execution_role_policy_attachment" {
  policy_arn = data.aws_iam_policy.ecsTaskExecutionRolePolicy.arn
  role       = aws_iam_role.execution_role.id
}
resource "aws_iam_role_policy" "test_policy" {
  name = "test_policy"
  role = aws_iam_role.execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Sid      = "ManageECR"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
        ]
      },
      {
        Sid    = "AllowSecretsManager",
        Effect = "Allow",
        Action = [
          "secretsmanager:*"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "execution_role" {
  name = "backstage_task_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
  tags = local.tags
}

data "aws_vpc_endpoint_service" "ecr_dkr" {
  service = "ecr.dkr"
}

# data "aws_iam_policy_document" "ecr_dkr_vpc_endpoint_policy" {
#   statement {
#     sid = "AllowPull"
#     actions = [
#       "ecr:BatchGetImage",
#       "ecr:GetDownloadUrlForLayer",
#       "ecr:GetAuthorizationToken"
#     ]
#     resources = ["*"]
#     principals {
#       type        = "AWS"
#       identifiers = "*"
#     }
#   }
# {
#     }
# }

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = aws_vpc.backstage_vpc.id
  service_name      = data.aws_vpc_endpoint_service.ecr_dkr.service_name
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.backstage_security_group.id]
  subnet_ids         = [aws_subnet.backstage_subnet_a.id, aws_subnet.backstage_subnet_b.id]

  # Set VPC endpoint policy to limit to pull images from Amazon ECR only
  # https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html#ecr-vpc-endpoint-policy
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAll",
      Principal = "*",
      Action    = "*",
      Effect    = "Allow",
      Resource  = "*"
    }]
  })

  # Private DNS hostname is required.
  # https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html#ecr-setting-up-vpc-create
  private_dns_enabled = true

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "start_ecs_task" {
  name              = "/ecs/backstagecontainer"
  retention_in_days = 7

  tags = local.tags
}

resource "aws_ecs_task_definition" "backstage_task_definition" {
  family = "backstage_service"
  container_definitions = jsonencode([
    {
      name      = "first"
      image     = "${aws_ecr_repository.backstage_ecr.repository_url}:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"       = "${aws_cloudwatch_log_group.start_ecs_task.name}",
          "awslogs-region"      = "eu-west-1",
          awslogs-stream-prefix = "/ecs"
        }
      },
    },
  ])

  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  execution_role_arn = aws_iam_role.execution_role.arn
  # task_role_arn      = aws_iam_role.task_role.arn

  cpu          = 256
  memory       = 512
  network_mode = "awsvpc"

  tags = local.tags
}


resource "aws_ecs_service" "backstage_service" {
  name          = "backstage"
  cluster       = aws_ecs_cluster.backstage_fargate_cluster.id
  desired_count = 1

  network_configuration {
    subnets         = [aws_subnet.backstage_subnet_a.id, aws_subnet.backstage_subnet_b.id]
    security_groups = [aws_security_group.backstage_security_group.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backstage_vpc_alb_target_group.arn
    container_port = 80
    container_name = "first"
  }

  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.backstage_task_definition.arn
  force_new_deployment = true
}
