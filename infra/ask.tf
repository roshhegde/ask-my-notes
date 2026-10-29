# Step 3: POST /ask -> embed the question, find the closest chunks, answer with Nova Micro.

data "archive_file" "ask" {
  type        = "zip"
  source_file = "${path.module}/../lambdas/ask/handler.py"
  output_path = "${path.module}/../build/ask.zip"
}

resource "aws_iam_role" "ask" {
  name = "${var.project_name}-ask"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Read-only on the index, plus the two models it calls.
resource "aws_iam_role_policy" "ask" {
  role = aws_iam_role.ask.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.notes.arn
        Condition = {
          StringLike = { "s3:prefix" = ["index/*"] }
        }
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.notes.arn}/index/*"
      },
      {
        # Converse uses the bedrock:InvokeModel permission.
        Effect = "Allow"
        Action = "bedrock:InvokeModel"
        Resource = [
          "arn:aws:bedrock:${var.region}::foundation-model/${var.embed_model_id}",
          "arn:aws:bedrock:${var.region}::foundation-model/${var.chat_model_id}",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.ask.arn}:*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "ask" {
  name              = "/aws/lambda/${var.project_name}-ask"
  retention_in_days = 7
}

resource "aws_lambda_function" "ask" {
  function_name    = "${var.project_name}-ask"
  role             = aws_iam_role.ask.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  filename         = data.archive_file.ask.output_path
  source_code_hash = data.archive_file.ask.output_base64sha256
  memory_size      = 512 # more memory = more CPU for the similarity math
  timeout          = 30

  environment {
    variables = {
      NOTES_BUCKET     = aws_s3_bucket.notes.bucket
      EMBED_MODEL_ID   = var.embed_model_id
      EMBED_DIMENSIONS = "256"
      CHAT_MODEL_ID    = var.chat_model_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.ask]
}

# HTTP API (not REST API): about 70% cheaper and simpler. No auth yet, so
# throttling is what stops a stranger from running up your Bedrock bill.
resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "ask" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ask.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ask" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /ask"
  target    = "integrations/${aws_apigatewayv2_integration.ask.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 1 # requests per second
    throttling_burst_limit = 3
  }
}

resource "aws_lambda_permission" "api_invoke_ask" {
  statement_id  = "AllowHttpApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ask.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*/ask"
}
