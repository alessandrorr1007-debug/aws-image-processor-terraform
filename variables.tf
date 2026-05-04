variable "environment" {
  description = "Entorno de despliegue (dev, qa, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "account_suffix" {
  description = "Sufijo para evitar nombres duplicados en S3"
  type        = string
}