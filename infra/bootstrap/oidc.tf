# Acceso de GitHub Actions por OIDC: rol de plan (solo lectura) y rol de deploy (recursos ecobyte-*).
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  state_bucket_arn = "arn:aws:s3:::ecobyte-agro-tfstate-${local.account_id}"

  arn_prefix = "arn:aws:%s:${local.region}:${local.account_id}"
  oidc_host  = "token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [for p in var.github_sub_prefixes : "${p}:pull_request"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name               = "ecobyte-github-plan"
  description        = "tofu plan desde pull requests: solo lectura"
  assume_role_policy = data.aws_iam_policy_document.github_plan_trust.json
}

data "aws_iam_policy_document" "read" {
  statement {
    sid = "ReadServices"
    actions = [
      "sqs:Get*",
      "sqs:List*",
      "sns:Get*",
      "sns:List*",
      "dynamodb:Describe*",
      "dynamodb:List*",
      "lambda:Get*",
      "lambda:List*",
      "logs:Describe*",
      "logs:List*",
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "iam:Get*",
      "iam:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadAlertEmails"
    actions   = ["ssm:GetParameter"]
    resources = [format("${local.arn_prefix}:parameter/ecobyte/alert-emails", "ssm")]
  }
}

data "aws_iam_policy_document" "github_plan" {
  source_policy_documents = [data.aws_iam_policy_document.read.json]

  statement {
    sid       = "StateRead"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/envs/*"]
  }

  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["envs/*"]
    }
  }

  statement {
    sid       = "StateLock"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/envs/*.tflock"]
  }
}

resource "aws_iam_role_policy" "github_plan" {
  name   = "plan-solo-lectura"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan.json
}

data "aws_iam_policy_document" "github_deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [for p in var.github_sub_prefixes : "${p}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "ecobyte-github-deploy"
  description        = "tofu apply y destroy desde el environment aprobado"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_trust.json
}

data "aws_iam_policy_document" "github_deploy" {
  source_policy_documents = [data.aws_iam_policy_document.read.json]

  statement {
    sid       = "StateReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/envs/*"]
  }

  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["envs/*"]
    }
  }

  statement {
    sid     = "ManageQueuesAndTopics"
    actions = ["sqs:*", "sns:*"]
    resources = [
      format("${local.arn_prefix}:ecobyte-*", "sqs"),
      format("${local.arn_prefix}:ecobyte-*", "sns"),
    ]
  }

  statement {
    sid       = "ManageTables"
    actions   = ["dynamodb:*"]
    resources = [format("${local.arn_prefix}:table/ecobyte-*", "dynamodb")]
  }

  statement {
    sid       = "ManageFunctions"
    actions   = ["lambda:*"]
    resources = [format("${local.arn_prefix}:function:ecobyte-*", "lambda")]
  }

  statement {
    sid = "ManageEventSourceMappings"
    actions = [
      "lambda:CreateEventSourceMapping",
      "lambda:UpdateEventSourceMapping",
      "lambda:DeleteEventSourceMapping",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "TagEventSourceMappings"
    actions   = ["lambda:TagResource", "lambda:UntagResource"]
    resources = [format("${local.arn_prefix}:event-source-mapping:*", "lambda")]
  }

  statement {
    sid     = "ManageLogGroups"
    actions = ["logs:*"]
    resources = [
      format("${local.arn_prefix}:log-group:/aws/lambda/ecobyte-*", "logs"),
      format("${local.arn_prefix}:log-group:/aws/lambda/ecobyte-*:*", "logs"),
    ]
  }

  statement {
    sid = "ManageAlarmsAndDashboards"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:PutDashboard",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = [
      format("${local.arn_prefix}:alarm:ecobyte-*", "cloudwatch"),
      "arn:aws:cloudwatch::${local.account_id}:dashboard/ecobyte-*",
    ]
  }

  statement {
    sid = "ManageEcobyteRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/ecobyte-*"]
  }

  statement {
    sid       = "AttachEcobytePolicies"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = ["arn:aws:iam::${local.account_id}:role/ecobyte-*"]

    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::${local.account_id}:policy/ecobyte-*"]
    }
  }

  statement {
    sid = "ManageEcobytePolicies"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:policy/ecobyte-*"]
  }

  statement {
    sid       = "PassRoleToLambda"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/ecobyte-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid       = "ProtectGithubRoles"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["arn:aws:iam::${local.account_id}:role/ecobyte-github-*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy-ecobyte"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
