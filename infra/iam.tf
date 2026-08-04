# --- Execution role: what the ECS AGENT needs to start the container ---
# (pull from ECR, write logs, fetch secrets BEFORE the container's code runs)
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

# AWS-managed policy covering the standard execution needs: ECR pull,
# CloudWatch Logs write. Using the managed policy instead of writing our
# own is the norm here — it's exactly scoped for this purpose and AWS
# keeps it updated.
resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The managed policy above does NOT include Secrets Manager access — that's
# not part of "standard" execution, so we grant it explicitly, and scope it
# to only the one secret this project needs (not "all secrets in the account").
data "aws_iam_policy_document" "ecs_execution_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.rds_password.arn,
      aws_secretsmanager_secret.database_url.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "${var.project_name}-ecs-execution-secrets"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution_secrets.json
}

# --- Task role: what the APPLICATION ITSELF can do at runtime ---
# Our app talks to Postgres over the network, not via AWS APIs, so this
# stays empty for now. Created anyway so there's somewhere to add
# permissions later without restructuring anything.
resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

# --- Grafana's CloudWatch datasource: read-only, nothing else ---
# Deliberately NOT reusing terraform-deployer here — that user can create/
# destroy all of AWS. Grafana only ever needs to READ metric data, so it
# gets its own narrow user, same principle as the ECS execution role's
# secrets policy above (scoped to exactly what's needed, nothing more).
resource "aws_iam_user" "grafana_readonly" {
  name = "${var.project_name}-grafana-readonly"
}

data "aws_iam_policy_document" "grafana_cloudwatch_read" {
  statement {
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:DescribeAlarmsForMetric",
      "tag:GetResources", # the CloudWatch datasource uses this for tag-based filtering in the UI
    ]
    resources = ["*"] # CloudWatch read actions don't support resource-level scoping — this IS the least-privilege ceiling here
  }
}

resource "aws_iam_user_policy" "grafana_cloudwatch_read" {
  name   = "${var.project_name}-grafana-cloudwatch-read"
  user   = aws_iam_user.grafana_readonly.name
  policy = data.aws_iam_policy_document.grafana_cloudwatch_read.json
}

# Programmatic keys for Grafana to authenticate with — retrieved once via
# `terraform output`, pasted into Grafana's datasource config, never
# committed anywhere.
resource "aws_iam_access_key" "grafana_readonly" {
  user = aws_iam_user.grafana_readonly.name
}
