# DLQ para mensajes que fallaron al procesarse
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-ingesta-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

# Cola de ingesta que recibe las lecturas del simulador. Luego de max_receive_count intentos fallidos, SQS mueve el mensaje a la DLQ.
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

# Solo la cola de ingesta puede mandar mensajes a la DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.ingest.arn]
  })
}

# Tópico de alertas: temperatura sobre 35 °C y alarma de la DLQ. No se cifra porque las alarmas de CloudWatch no pueden publicar en un tópico cifrado con
# la clave gestionada por AWS . El tópico solo lleva textos de alerta, sin datos sensibles.
#trivy:ignore:AWS-0095
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alertas"
}

# El correo exige confirmación manual: SNS manda un mensaje y la suscripción queda pendiente hasta que alguien aprieta el enlace.
resource "aws_sns_topic_subscription" "email" {
  count = length(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

# ---------------------------------------------------------------------------
# Identidad del simulador: solo puede enviar mensajes a la cola de ingesta.
# El simulador corre en la laptop con un perfil que asume este rol, así no usa
# los permisos del usuario de cada integrante. SendMessageBatch usa el mismo permiso.
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# La confianza es la cuenta: solo los usuarios de la cuenta con permiso de sts:AssumeRole
# sobre este rol pueden asumirlo. Nadie de afuera de la cuenta.
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

# Las colas usan cifrado gestionado por SQS (SSE-SQS), que no pide permisos de KMS.
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
