# Variables del bootstrap: entorno, límite del presupuesto y repos que pueden desplegar.
variable "env" {
  description = "Nombre del entorno, usado en la etiqueta env"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env debe ser dev o prod."
  }
}

variable "budget_limit_usd" {
  description = "Límite mensual del presupuesto en USD"
  type        = number
  default     = 5

  validation {
    condition     = var.budget_limit_usd > 0
    error_message = "El límite debe ser mayor que 0."
  }
}

variable "github_sub_prefixes" {
  description = "Prefijos del claim sub de los tokens OIDC de GitHub, uno por repo que puede desplegar, con los IDs numéricos de dueño y repo (se ve con: gh api repos/<dueño>/<repo>/actions/oidc/customization/sub). Son el repo original y el fork de la compañera, que se usa mientras Actions está bloqueado en el original."
  type        = list(string)
  default = [
    "repo:maurobarrales25@131790697/ecobyte-agro@1436055208",
    "repo:mikadominguezz@131786494/ecobyte-agro@1462922547",
  ]

  validation {
    condition = length(var.github_sub_prefixes) > 0 && alltrue([
      for p in var.github_sub_prefixes : can(regex("^repo:[A-Za-z0-9-]+@[0-9]+/[A-Za-z0-9._-]+@[0-9]+$", p))
    ])
    error_message = "Cada prefijo debe tener el formato repo:dueño@ID/repo@ID, y tiene que haber al menos uno."
  }
}

variable "github_environment" {
  description = "Environment de GitHub (con aprobación manual) que puede asumir el rol de despliegue"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.github_environment))
    error_message = "github_environment solo admite letras, números, punto, guion y guion bajo."
  }
}
