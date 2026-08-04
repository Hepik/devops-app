# --- ALB: the only thing exposed directly to the internet ---
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow inbound HTTP from the internet to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "ALB can reach anything (needed to reach ECS tasks)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# --- ECS tasks (both frontend and backend): only reachable FROM the ALB ---
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Allow inbound only from the ALB, on the ports each service listens on"
  vpc_id      = aws_vpc.main.id

  # frontend (nginx)
  ingress {
    description     = "Frontend port from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # backend (express)
  ingress {
    description     = "Backend port from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Tasks can reach anything (ECR pull, RDS, etc - no NAT so this relies on public IP)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ecs-tasks-sg" }
}

# --- RDS: only reachable FROM the ECS tasks, never from the internet ---
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound Postgres only from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  # No egress block here on purpose. IMPORTANT Terraform gotcha: AWS
  # attaches a default "allow all outbound" rule when a security group is
  # created via the API — but Terraform's aws_security_group resource
  # manages the FULL rule set you declare. Zero egress blocks declared
  # means Terraform actively removes that default and leaves NO outbound
  # rules at all (not "default allow"). That's fine here specifically
  # because RDS never initiates outbound connections — but this same
  # omission on a resource that DOES need to call out (ECS tasks, above)
  # would silently break it, which is why ecs_tasks has an explicit
  # egress block and this one does not.

  tags = { Name = "${var.project_name}-rds-sg" }
}
