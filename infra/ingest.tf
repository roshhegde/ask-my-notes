# Step 2: when a note lands in notes/, chunk it and embed it with Titan.

data "aws_caller_identity" "current" {}

data "archive_file" "ingest" {
  type        = "zip"
  source_file = "${path.module}/../lambdas/ingest/handler.py"
  output_path = "${path.module}/../build/ingest.zip"
}

resource "aws_iam_role" "ingest" {
  name = "${var.project_name}-ingest"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Least privilege: read notes/, write index/, call one embedding model, write its own logs.
resource "aws_iam_role_policy" "ingest" {
  role = aws_iam_role.ingest.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.notes.arn}/notes/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.notes.arn}/index/*"
      },
      {
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = "arn:aws:bedrock:${var.region}::foundation-model/${var.embed_model_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.ingest.arn}:*"
      },
    ]
  })
}

# Created by Terraform (not Lambda) so it has a short retention and is
# removed by `terraform destroy`.
resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${var.project_name}-ingest"
  retention_in_days = 7
}

resource "aws_lambda_function" "ingest" {
  function_name    = "${var.project_name}-ingest"
  role             = aws_iam_role.ingest.arn
  runtime          = "python3.12"
  architectures    = ["arm64"] # Graviton is about 20% cheaper per GB-second
  handler          = "handler.handler"
  filename         = data.archive_file.ingest.output_path
  source_code_hash = data.archive_file.ingest.output_base64sha256
  memory_size      = 256
  # MAX_CHUNKS in handler.py caps Bedrock calls per file. No reserved
  # concurrency: new accounts often have a limit of 10, and reserving any
  # of it makes the apply fail.
  timeout = 120

  environment {
    variables = {
      EMBED_MODEL_ID   = var.embed_model_id
      EMBED_DIMENSIONS = "256"
    }
  }

  depends_on = [aws_cloudwatch_log_group.ingest]
}

resource "aws_lambda_permission" "s3_invoke_ingest" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.ingest.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.notes.arn
  source_account = data.aws_caller_identity.current.account_id
}

# Only notes/ triggers ingest. Writing to index/ must not, or the Lambda
# would trigger itself in a loop.
resource "aws_s3_bucket_notification" "notes" {
  bucket = aws_s3_bucket.notes.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "notes/"
  }

  depends_on = [aws_lambda_permission.s3_invoke_ingest]
}
