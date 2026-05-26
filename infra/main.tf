
# ─────────────────────────────────────────────────────────────────────────────
# Remote backend — state stored in S3, locking via DynamoDB
# (Provisioned by the bootstrap/ folder)
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  backend "s3" {
    bucket         = "tfstate-test-spark-fetch-falzpvkj"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tflock-test-spark-fetch-falzpvkj"
    encrypt        = true
  }
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "random_string" "suffix" {
  length  = 18
  special = false
  upper   = false
}

resource "aws_s3_bucket" "glue_scripts" {
  bucket        = "${var.glue_scripts_bucket_base_name}-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "output_data" {
  bucket        = "${var.output_data_bucket_base_name}-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "output_data" {
  bucket = aws_s3_bucket.output_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output_data" {
  bucket = aws_s3_bucket.output_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "glue_scripts" {
  bucket                  = aws_s3_bucket.glue_scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "output_data" {
  bucket                  = aws_s3_bucket.output_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "local_file" "glue_test_script" {
  filename = "${path.module}/glue_test_script.py"
  content  = <<-EOF
print("Hello from TEST script")
EOF
}

data "archive_file" "glue_test_script_zip" {
  type        = "zip"
  source_file = local_file.glue_test_script.filename
  output_path = "${path.module}/glue_test_script.zip"
}

resource "aws_s3_object" "glue_test_script_zip" {
  bucket       = aws_s3_bucket.glue_scripts.id
  key          = "scripts/glue_test_script.zip"
  source       = data.archive_file.glue_test_script_zip.output_path
  content_type = "application/zip"
  etag         = data.archive_file.glue_test_script_zip.output_md5
}

data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "glue-job-role-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_admin" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_glue_job" "api_to_s3" {
  name              = "api-to-s3-${random_string.suffix.result}"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  max_retries       = 0
  timeout           = 2880
  number_of_workers = 2
  worker_type       = "G.1X"
  execution_class   = "STANDARD"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/${aws_s3_object.glue_test_script_zip.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-metrics"                   = ""
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--TempDir"                          = "s3://${aws_s3_bucket.glue_scripts.bucket}/temp/"
    "--output_bucket"                    = aws_s3_bucket.output_data.bucket
    "--api_endpoint"                     = var.external_api_endpoint
  }

  depends_on = [
    aws_s3_object.glue_test_script_zip,
    aws_s3_bucket_versioning.glue_scripts,
    aws_s3_bucket_versioning.output_data,
    aws_s3_bucket_server_side_encryption_configuration.glue_scripts,
    aws_s3_bucket_server_side_encryption_configuration.output_data,
    aws_s3_bucket_public_access_block.glue_scripts,
    aws_s3_bucket_public_access_block.output_data,
    aws_iam_role_policy_attachment.glue_service,
    aws_iam_role_policy_attachment.glue_admin
  ]
}



# ─────────────────────────────────────────────────────────────────────────────
# IAM — Lambda
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "lambda-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "lambda-policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadLambdaZip"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.scripts.arn}/lambda/*"
      },
      {
        Sid    = "S3WriteOutput"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Lambda Function
# ─────────────────────────────────────────────────────────────────────────────
resource "local_file" "lambda_placeholder" {
  filename = "${path.module}/lambda_function.py"
  content  = <<-EOT
def lambda_handler(event, context):
    print("Hello from Lambda placeholder")
    return {
        "statusCode": 200,
        "body": "placeholder - will be replaced by CD pipeline"
    }
EOT
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_placeholder.filename
  output_path = "${path.module}/lambda_function.zip"
  depends_on  = [local_file.lambda_placeholder]
}

resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.scripts.id
  key    = "lambda/lambda_function.zip"
  source = data.archive_file.lambda_zip.output_path
  etag   = data.archive_file.lambda_zip.output_md5

  depends_on = [data.archive_file.lambda_zip]
}

resource "aws_lambda_function" "api_fetcher" {
  s3_bucket     = aws_s3_bucket.scripts.bucket
  s3_key        = "lambda/lambda_function.zip"
  function_name = "api-fetcher-${random_string.suffix.result}"
  role          = aws_iam_role.lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60

  depends_on = [
    aws_s3_object.lambda_zip,
    aws_iam_role_policy.lambda,
    aws_iam_role_policy_attachment.lambda_s3_full_access
  ]
}
resource "aws_iam_role_policy_attachment" "lambda_s3_full_access" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}