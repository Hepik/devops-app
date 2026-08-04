# Tells AWS to trust tokens issued by GitHub Actions' OIDC provider.
# One of these per AWS account, regardless of how many repos/roles use it.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's OIDC root CA thumbprint — AWS requires this to validate the
  # provider's cert chain. This is GitHub's published value, not something
  # specific to our account.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Trust policy: WHO can assume this role. Scoped tightly — only workflow
# runs triggered from pushes to `main` in this exact repo can get in.
# Compare to a stolen long-lived access key, which works from anywhere,
# forever, until manually revoked.
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Hepik/devops-app:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

# What CI is actually allowed to DO once it assumes this role — scoped to
# exactly the actions backend-ecs.yml/frontend-ecs.yml perform, nothing
# resembling terraform-deployer's full admin access.
data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this specific action doesn't support resource-level scoping
  }

  statement {
    sid = "ECRPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [
      aws_ecr_repository.backend.arn,
      aws_ecr_repository.frontend.arn,
    ]
  }

  statement {
    sid = "ECSDeploy"
    actions = [
      "ecs:DescribeTaskDefinition", # doesn't support resource-level scoping
      "ecs:RegisterTaskDefinition",  # same
    ]
    resources = ["*"]
  }

  statement {
    sid = "ECSUpdateService"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [
      "arn:aws:ecs:${var.aws_region}:*:service/${aws_ecs_cluster.main.name}/${aws_ecs_service.backend.name}",
      "arn:aws:ecs:${var.aws_region}:*:service/${aws_ecs_cluster.main.name}/${aws_ecs_service.frontend.name}",
    ]
  }

  # register-task-definition requires permission to hand the execution/task
  # roles to ECS — without this, CI can build the task def JSON but AWS
  # rejects registering it.
  statement {
    sid       = "PassRolesToECS"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_actions_permissions" {
  name   = "${var.project_name}-github-actions-permissions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

output "github_actions_role_arn" {
  description = "Paste this into the workflow files' role-to-assume field"
  value       = aws_iam_role.github_actions.arn
}
