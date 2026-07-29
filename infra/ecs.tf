resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# Log retention set explicitly — without it, CloudWatch keeps logs forever
# (small but needless cost/clutter for a learning project).
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project_name}-backend"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.project_name}-frontend"
  retention_in_days = 7
}

# --- Backend task definition ---
resource "aws_ecs_task_definition" "backend" {
  family = "${var.project_name}-backend"

  # awsvpc is REQUIRED for Fargate — it's what gives each task its own ENI
  # (network interface) and IP address, which is why Target Groups above
  # use target_type = "ip" rather than "instance".
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256 # 0.25 vCPU — smallest Fargate size
  memory                   = 512 # 0.5 GB

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn       = aws_iam_role.ecs_task.arn

  # container_definitions is a JSON string in the AWS API — jsonencode()
  # again, same reason as the ECR lifecycle policy earlier.
  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:${var.backend_image_tag}"
      essential = true

      portMappings = [
        { containerPort = 5000, protocol = "tcp" }
      ]

      environment = [
        { name = "PORT", value = "5000" },
        { name = "DB_SSL", value = "true" } # RDS rejects unencrypted connections; see backend/server.js
      ]

      # Resolved from Secrets Manager by the EXECUTION role at container
      # start — the app just sees a normal DATABASE_URL env var, never
      # knows Secrets Manager is involved.
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.database_url.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])
}

# --- Frontend task definition ---
resource "aws_ecs_task_definition" "frontend" {
  family = "${var.project_name}-frontend"

  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn       = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = "${aws_ecr_repository.frontend.repository_url}:${var.frontend_image_tag}"
      essential = true

      portMappings = [
        { containerPort = 80, protocol = "tcp" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "frontend"
        }
      }
    }
  ])
}

# --- Services: keep the desired task(s) running and wired to the ALB ---
resource "aws_ecs_service" "backend" {
  name            = "${var.project_name}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true # no NAT — tasks need a public IP to pull from ECR / reach out
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name    = "backend"
    container_port    = 5000
  }

  # After the first apply, CI owns which task definition revision is live
  # (it registers new revisions and calls ecs update-service on every
  # deploy). Without this, the next `terraform apply` would see that drift
  # and silently roll the service back to var.backend_image_tag = "initial".
  lifecycle {
    ignore_changes = [task_definition]
  }

  # The service registers tasks into the target group, which only works
  # once the ALB is actually listening — without this, ECS and the ALB
  # setup could race each other on a fresh `apply`.
  depends_on = [aws_lb_listener.http]
}

resource "aws_ecs_service" "frontend" {
  name            = "${var.project_name}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name    = "frontend"
    container_port    = 80
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.http]
}
