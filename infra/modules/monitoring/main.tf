# Alarma de la DLQ y dashboard de CloudWatch del pipeline.
resource "aws_cloudwatch_metric_alarm" "dlq_has_messages" {
  alarm_name        = "${var.name_prefix}-dlq-con-mensajes"
  alarm_description = "Hay lecturas que fallaron y no se guardaron"
  namespace         = "AWS/SQS"
  metric_name       = "ApproximateNumberOfMessagesVisible"
  dimensions = {
    QueueName = var.dlq_queue_name
  }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alerts_topic_arn]
}

data "aws_region" "current" {}

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          title   = "Cola de ingesta: mensajes esperando"
          region  = data.aws_region.current.region
          period  = 60
          stat    = "Maximum"
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.ingest_queue_name]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          title   = "DLQ: lecturas que fallaron"
          region  = data.aws_region.current.region
          period  = 60
          stat    = "Maximum"
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_queue_name]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          title   = "Lambda: invocaciones"
          region  = data.aws_region.current.region
          period  = 60
          stat    = "Sum"
          metrics = [["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_name]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          title   = "Lambda: errores"
          region  = data.aws_region.current.region
          period  = 60
          stat    = "Sum"
          metrics = [["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_name]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          title  = "Lambda: duración (ms)"
          region = data.aws_region.current.region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "Average", label = "promedio" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "p95", label = "p95" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "Maximum", label = "máximo" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6

        properties = {
          title   = "Lambda: ejecuciones concurrentes"
          region  = data.aws_region.current.region
          period  = 60
          stat    = "Maximum"
          metrics = [["AWS/Lambda", "ConcurrentExecutions", "FunctionName", var.lambda_function_name]]
        }
      }
    ]
  })
}
