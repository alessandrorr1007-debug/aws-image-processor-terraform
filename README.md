# AWS Image Processor - Terraform IaC Project

## Descripción del proyecto

Este proyecto implementa una arquitectura serverless en AWS utilizando Terraform (Infrastructure as Code).  
El sistema procesa imágenes subidas a un bucket S3, las envía a una cola SQS y las procesa mediante funciones Lambda.

La arquitectura está diseñada para ser desplegable en 3 entornos: DEV, QA y PROD, usando archivos de variables (`tfvars`).

---

## Arquitectura

El sistema incluye los siguientes servicios AWS:

- Amazon S3 (almacenamiento de imágenes)
- AWS Lambda (procesamiento de imágenes)
- Amazon SQS (cola de eventos)
- API Gateway (endpoint HTTP)
- IAM Roles (seguridad)
- CloudWatch (logs y monitoreo)
- VPC con subnets públicas y privadas

Entornos
DEV
QA
PROD

Configuración mediante:

envs/dev.tfvars
envs/qa.tfvars
envs/prod.tfvars

Despliegue

Inicializar Terraform:

terraform init

Desplegar DEV:

terraform apply -var-file="envs/dev.tfvars"

Destruir infraestructura:

terraform destroy -var-file="envs/dev.tfvars"