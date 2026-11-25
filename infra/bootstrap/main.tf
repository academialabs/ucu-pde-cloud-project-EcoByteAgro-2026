# Presupuesto mensual de USD 5 con avisos por email; los correos se leen de SSM.
data "aws_ssm_parameter" "budget_emails" {
  name = "/ecobyte/budget-emails"
}

locals {
  budget_emails = jsondecode(data.aws_ssm_parameter.budget_emails.value)
}

resource "aws_budgets_budget" "monthly" {
  name         = "ecobyte-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  lifecycle {
    ignore_changes = [metrics]
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = local.budget_emails
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = local.budget_emails
  }
}
