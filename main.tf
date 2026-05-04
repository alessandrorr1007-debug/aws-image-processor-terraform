data "aws_availability_zones" "available" {}

# VPC


resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-image-processor-${var.environment}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}


# SUBNETS


resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}


# NAT


resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.igw]
}


# ROUTES


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}


# S3


resource "aws_s3_bucket" "images" {
  bucket = "image-processor-${var.environment}-${var.account_suffix}"
}


# SQS


resource "aws_sqs_queue" "dlq" {
  name = "image-processor-${var.environment}-dlq"
}

resource "aws_sqs_queue" "main_queue" {
  name                       = "image-processor-${var.environment}-queue"
  visibility_timeout_seconds = 360

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "s3_to_sqs" {
  queue_url = aws_sqs_queue.main_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.main_queue.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = aws_s3_bucket.images.arn
        }
      }
    }]
  })
}


# S3 -> SQS


resource "aws_s3_bucket_notification" "s3_to_sqs" {
  bucket = aws_s3_bucket.images.id

  queue {
    queue_arn = aws_sqs_queue.main_queue.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.s3_to_sqs]
}


# IAM


resource "aws_iam_role" "upload_role" {
  name = "upload-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "crop_role" {
  name = "crop-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "upload_basic" {
  role       = aws_iam_role.upload_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "crop_basic" {
  role       = aws_iam_role.crop_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "crop_vpc" {
  role       = aws_iam_role.crop_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}


# SECURITY GROUP


resource "aws_security_group" "lambda_sg" {
  name   = "sg-lambda-${var.environment}"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# LAMBDAS


resource "aws_lambda_function" "upload" {
  function_name = "upload-${var.environment}"
  role          = aws_iam_role.upload_role.arn

  runtime = "nodejs20.x"
  handler = "index.handler"

  filename         = "lambda/lambda_dummy.zip"
  source_code_hash = filebase64sha256("lambda/lambda_dummy.zip")
}

resource "aws_lambda_function" "crop" {
  function_name = "crop-${var.environment}"
  role          = aws_iam_role.crop_role.arn

  runtime = "nodejs20.x"
  handler = "index.handler"

  filename         = "lambda/lambda_dummy.zip"
  source_code_hash = filebase64sha256("lambda/lambda_dummy.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.main_queue.arn
  function_name    = aws_lambda_function.crop.arn
  batch_size       = 5
}


# API GATEWAY


resource "aws_apigatewayv2_api" "http_api" {
  name          = "image-api-${var.environment}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "upload_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.upload.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.upload_integration.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload.function_name
  principal     = "apigateway.amazonaws.com"
}

# CLOUDWATCH + SNS

resource "aws_cloudwatch_log_group" "upload_logs" {
  name              = "/aws/lambda/upload-${var.environment}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "crop_logs" {
  name              = "/aws/lambda/crop-${var.environment}"
  retention_in_days = 14
}

resource "aws_sns_topic" "alerts" {
  name = "image-processor-alerts-${var.environment}"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}