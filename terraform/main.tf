// creating the bucket for state persistence
// aws s3api create-bucket --bucket terraform-state-affonso-unique-id --region us-east-1
// aws s3api put-bucket-versioning --bucket terraform-state-affonso-unique-id --versioning-configuration Status=Enabled

terraform {
  backend "s3" {
    bucket = "terraform-state-affonso-unique-id"
    key    = "aws-event-driven/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- SQS INFRASTRUCTURE ---

# Dead Letter Queue (DLQ) for failed orders
resource "aws_sqs_queue" "orders_dlq" {
  name                        = "orders-fifo-dlq-affonso.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

# Main queue for order processing
resource "aws_sqs_queue" "orders_queue" {
  name                        = "orders-fifo-queue-affonso.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount     = 3
  })
}

# --- IAM PERMISSIONS ---

# IAM Role for the Pre-Validation Lambda
resource "aws_iam_role" "lambda_pre_val_role" {
  name = "lambda-pre-validation-role-affonso"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Policy to allow Lambda to send messages to SQS and write logs
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-pre-validation-policy"
  role = aws_iam_role.lambda_pre_val_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["sqs:SendMessage"]
        Effect   = "Allow"
        Resource = aws_sqs_queue.orders_queue.arn
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Permissão para a Lambda escrever na tabela do DynamoDB
resource "aws_iam_role_policy" "lambda_dynamo_write" {
  name = "lambda_dynamo_write_policy"
  role = aws_iam_role.order_proc_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:dynamodb:us-east-1:*:table/orders-db-affonso" #
      }
    ]
  })
}

# --- LAMBDA FUNCTION ---

# Zip the Python code automatically before deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/pre_validation.py"
  output_path = "${path.module}/lambda_function.zip"
}

# Pre-Validation Lambda Function
resource "aws_lambda_function" "pre_validation_lambda" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "pre-validation-lambda-affonso"
  role          = aws_iam_role.lambda_pre_val_role.arn
  handler       = "pre_validation.lambda_handler"
  runtime       = "python3.12"

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.orders_queue.id
    }
  }
}

# --- API GATEWAY ---

# REST API Gateway
resource "aws_api_gateway_rest_api" "orders_api" {
  name        = "orders-api-affonso"
  description = "API for receiving orders"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Resource path /orders
resource "aws_api_gateway_resource" "orders_resource" {
  rest_api_id = aws_api_gateway_rest_api.orders_api.id
  parent_id   = aws_api_gateway_rest_api.orders_api.root_resource_id
  path_part   = "orders"
}

# POST Method
resource "aws_api_gateway_method" "orders_method" {
  rest_api_id   = aws_api_gateway_rest_api.orders_api.id
  resource_id   = aws_api_gateway_resource.orders_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda Integration (Proxy)
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.orders_api.id
  resource_id             = aws_api_gateway_resource.orders_resource.id
  http_method             = aws_api_gateway_method.orders_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pre_validation_lambda.invoke_arn
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_validation_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.orders_api.execution_arn}/*/*"
}

# Deployment and Stage
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.orders_api.id
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.orders_api.id
  stage_name    = "dev"
}

# Output the API URL to test it later
output "invoke_url" {
  value = "${aws_api_gateway_stage.api_stage.invoke_url}/orders"
}


# --- S3 INGESTION & TRACKING ---

# S3 Bucket for the Data Lake
resource "aws_s3_bucket" "datalake" {
  bucket = "datalake-orders-affonso"
}

# SNS Topic for Error Notifications
resource "aws_sns_topic" "error_notifications" {
  name = "order-file-errors-affonso"
}

# SNS Email Subscription (Replace with your email)
resource "aws_sns_topic_subscription" "error_email" {
  topic_arn = aws_sns_topic.error_notifications.arn
  protocol  = "email"
  endpoint  = "seu-email@exemplo.com" # Change this!
}

# DynamoDB Table for File Tracking
resource "aws_dynamodb_table" "file_history" {
  name         = "file-processing-history-affonso"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "fileName"

  attribute {
    name = "fileName"
    type = "S"
  }
}

# SQS Standard for S3 Events
resource "aws_sqs_queue" "s3_event_queue" {
  name                      = "s3-orders-queue-affonso"
  visibility_timeout_seconds = 70 # Higher than Lambda timeout
}

# Policy to allow S3 to send messages to SQS
resource "aws_sqs_queue_policy" "allow_s3_to_sqs" {
  queue_url = aws_sqs_queue.s3_event_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action = "sqs:SendMessage"
      Resource = aws_sqs_queue.s3_event_queue.arn
      Condition = {
        ArnLike = { "aws:SourceArn" = aws_s3_bucket.datalake.arn }
      }
    }]
  })
}

# S3 Event Notification to SQS
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.datalake.id

  queue {
    queue_arn     = aws_sqs_queue.s3_event_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".json"
  }
}

# IAM Role & Policy for S3 Validation Lambda
resource "aws_iam_role" "s3_val_role" {
  name = "lambda-s3-validation-role-affonso"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "s3_val_policy" {
  role = aws_iam_role.s3_val_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Action = ["s3:GetObject"], Effect = "Allow", Resource = "${aws_s3_bucket.datalake.arn}/*" },
      { Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Effect = "Allow", Resource = aws_sqs_queue.s3_event_queue.arn },
      { Action = ["sqs:SendMessage"], Effect = "Allow", Resource = aws_sqs_queue.orders_queue.arn }, # Sends to Day 1 Queue
      { Action = ["dynamodb:PutItem"], Effect = "Allow", Resource = aws_dynamodb_table.file_history.arn },
      { Action = ["sns:Publish"], Effect = "Allow", Resource = aws_sns_topic.error_notifications.arn },
      { Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Effect = "Allow", Resource = "*" }
    ]
  })
}

# Lambda S3 Validation Function
resource "aws_lambda_function" "s3_validation_lambda" {
  filename      = data.archive_file.s3_val_zip.output_path
  function_name = "s3-validation-lambda-affonso"
  role          = aws_iam_role.s3_val_role.arn
  handler       = "s3_validation.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.file_history.name
      SNS_TOPIC_ARN  = aws_sns_topic.error_notifications.arn
      SQS_FIFO_URL   = aws_sqs_queue.orders_queue.id
    }
  }
}

data "archive_file" "s3_val_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/s3_validation.py"
  output_path = "${path.module}/s3_validation_function.zip"
}

# SQS Trigger for Lambda
resource "aws_lambda_event_source_mapping" "sqs_s3_trigger" {
  event_source_arn = aws_sqs_queue.s3_event_queue.arn
  function_name    = aws_lambda_function.s3_validation_lambda.arn
  batch_size       = 1
}

# --- DAY 3: CENTRAL PROCESSING & PERSISTENCE ---

# 1. Custom Event Bus (The central communication hub)
resource "aws_cloudwatch_event_bus" "order_event_bus" {
  name = "orders-event-bus-affonso"
}

# 2. Main DynamoDB Table (Final destination for processed orders)
resource "aws_dynamodb_table" "main_orders_db" {
  name         = "orders-db-affonso"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }
}

# 3. Intermediate SQS for Pending Orders (Buffer between EventBridge and Lambda)
resource "aws_sqs_queue" "pending_orders_queue" {
  name                      = "orders-pending-queue-affonso"
  visibility_timeout_seconds = 70
}

# 4. EventBridge Rule (Routes "OrderValidated" events to the Pending Queue)
resource "aws_cloudwatch_event_rule" "order_validated_rule" {
  name           = "new-order-validated-rule-affonso"
  event_bus_name = aws_cloudwatch_event_bus.order_event_bus.name

  event_pattern = jsonencode({
    source      = ["lab.orders.validation"]
    detail-type = ["OrderValidated"]
  })
}

# Target: Link the Rule to the SQS Queue
resource "aws_cloudwatch_event_target" "sqs_target" {
  rule           = aws_cloudwatch_event_rule.order_validated_rule.name
  event_bus_name = aws_cloudwatch_event_bus.order_event_bus.name
  target_id      = "SendToSQS"
  arn            = aws_sqs_queue.pending_orders_queue.arn
}

# Permission for EventBridge to send messages to SQS
resource "aws_sqs_queue_policy" "eventbridge_to_sqs_policy" {
  queue_url = aws_sqs_queue.pending_orders_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action = "sqs:SendMessage"
      Resource = aws_sqs_queue.pending_orders_queue.arn
      Condition = {
        ArnLike = { "aws:SourceArn" = aws_cloudwatch_event_rule.order_validated_rule.arn }
      }
    }]
  })
}

# Permission for Lambda "puxar" and "apagar" messages from the FIFO queue
resource "aws_iam_role_policy" "lambda_sqs_processor_policy" {
  name = "lambda_sqs_processor_policy"
  role = aws_iam_role.order_proc_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.orders_queue.arn
      },
    ]
  })
}

# 5. Order Processing Lambda (Consumes from SQS and saves to DynamoDB)
resource "aws_iam_role" "order_proc_role" {
  name = "lambda-order-processing-role-affonso"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "order_proc_policy" {
  role = aws_iam_role.order_proc_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { 
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:SendMessage"], 
        Effect   = "Allow", 
        Resource = [
          aws_sqs_queue.pending_orders_queue.arn,
          aws_sqs_queue.global_lambda_dlq.arn
        ] 
      },
      { 
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"], 
        Effect   = "Allow", 
        # Fixed: Now correctly points to the Table ARN
        Resource = aws_dynamodb_table.main_orders_db.arn 
      },
      { 
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], 
        Effect   = "Allow", 
        Resource = "*" 
      }
    ]
  })
}

resource "aws_lambda_function" "order_processing_lambda" {
  filename      = data.archive_file.order_proc_zip.output_path
  function_name = "order-processing-lambda-affonso"
  role          = aws_iam_role.order_proc_role.arn
  handler       = "order_processing.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60

  source_code_hash = data.archive_file.order_proc_zip.output_base64sha256
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.main_orders_db.name
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.global_lambda_dlq.arn
  }
}

data "archive_file" "order_proc_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/order_processing.py"
  output_path = "${path.module}/order_processing_function.zip"
}

resource "aws_lambda_event_source_mapping" "sqs_proc_trigger" {
  event_source_arn = aws_sqs_queue.orders_queue.arn
  function_name    = aws_lambda_function.order_processing_lambda.arn
  batch_size       = 1
}

# --- DAY 4: RESILIENCE & MONITORING ---

# 1. Global Lambda DLQ (For any Lambda that fails to execute)
resource "aws_sqs_queue" "global_lambda_dlq" {
  name = "global-lambda-dlq-affonso"
}

# 2. CloudWatch Alarm: Alert if messages stay in the Main Queue for too long
resource "aws_cloudwatch_metric_alarm" "sqs_delay_alarm" {
  alarm_name          = "sqs-orders-delay-affonso"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "300" # 5 minutes
  alarm_description   = "This alarm triggers if an order is stuck in the queue for more than 5 minutes."
  alarm_actions       = [aws_sns_topic.error_notifications.arn]

  dimensions = {
    QueueName = aws_sqs_queue.orders_queue.name
  }
}

# 3. CloudWatch Log Group for better traceability (Professional Practice)
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/order-processing-lambda-affonso"
  retention_in_days = 7 # Saves money by not keeping logs forever
}