# Cola de ingesta con DLQ, tópico de alertas por email y rol del simulador (solo envía).
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-ingesta-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "ingest" {
  name                       = "${var.name_prefix}-ingesta"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.ingest.arn]
  })
}

#trivy:ignore:AWS-0095
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alertas"
}

resource "aws_sns_topic_subscription" "email" {
  count = length(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "simulator_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "simulator" {
  name               = "${var.name_prefix}-simulador"
  description        = "Simulador de sensores: solo envía mensajes a la cola de ingesta"
  assume_role_policy = data.aws_iam_policy_document.simulator_trust.json
}

data "aws_iam_policy_document" "simulator" {
  statement {
    sid       = "SendReadings"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.ingest.arn]
  }
}

resource "aws_iam_role_policy" "simulator" {
  name   = "simulador-solo-envia"
  role   = aws_iam_role.simulator.id
  policy = data.aws_iam_policy_document.simulator.json
}
