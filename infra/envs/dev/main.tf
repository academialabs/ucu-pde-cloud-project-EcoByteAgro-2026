# Entorno dev: conecta los módulos messaging, database, consumer y monitoring.
data "aws_ssm_parameter" "alert_emails" {
  name = "/ecobyte/alert-emails"
}

module "messaging" {
  source = "../../modules/messaging"

  name_prefix  = "ecobyte-${var.env}"
  alert_emails = jsondecode(data.aws_ssm_parameter.alert_emails.value)
}

module "database" {
  source = "../../modules/database"

  name_prefix = "ecobyte-${var.env}"
}

module "consumer" {
  source = "../../modules/consumer"

  name_prefix        = "ecobyte-${var.env}"
  source_dir         = "${path.root}/../../../app/lambda"
  queue_arn          = module.messaging.ingest_queue_arn
  alerts_topic_arn   = module.messaging.alerts_topic_arn
  table_name         = module.database.table_name
  table_arn          = module.database.table_arn
  ttl_attribute_name = module.database.ttl_attribute_name
}

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix          = "ecobyte-${var.env}"
  ingest_queue_name    = module.messaging.ingest_queue_name
  dlq_queue_name       = module.messaging.dlq_name
  lambda_function_name = module.consumer.function_name
  alerts_topic_arn     = module.messaging.alerts_topic_arn
}

