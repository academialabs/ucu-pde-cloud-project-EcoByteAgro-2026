# Versiones requeridas del módulo database.
terraform {
  required_version = ">= 1.12.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
