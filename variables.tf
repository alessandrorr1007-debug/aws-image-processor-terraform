variable "environment" {
  description = "Entorno (dev, qa, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "account_suffix" {
  description = "Sufijo único S3"
  type        = string
}

variable "alert_email" {
  description = "Correo para alertas"
  type        = string
}