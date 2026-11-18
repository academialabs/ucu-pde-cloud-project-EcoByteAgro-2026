# Tabla de lecturas en DynamoDB: clave sensor + timestamp y TTL de 30 días.
resource "aws_dynamodb_table" "readings" {
  name         = "${var.name_prefix}-lecturas"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sensor_id"
  range_key    = "timestamp"

  attribute {
    name = "sensor_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  ttl {
    attribute_name = var.ttl_attribute_name
    enabled        = true
  }

  deletion_protection_enabled = false

}
