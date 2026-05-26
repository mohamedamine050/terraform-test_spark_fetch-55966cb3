output "random_suffix" {
  value = random_string.suffix.result
}

output "glue_scripts_bucket_name" {
  value = aws_s3_bucket.glue_scripts.id
}

output "glue_scripts_bucket_arn" {
  value = aws_s3_bucket.glue_scripts.arn
}

output "glue_scripts_bucket_domain_name" {
  value = aws_s3_bucket.glue_scripts.bucket_domain_name
}

output "glue_scripts_bucket_regional_domain_name" {
  value = aws_s3_bucket.glue_scripts.bucket_regional_domain_name
}

output "glue_scripts_bucket_region" {
  value = data.aws_region.current.name
}

output "output_data_bucket_name" {
  value = aws_s3_bucket.output_data.id
}

output "output_data_bucket_arn" {
  value = aws_s3_bucket.output_data.arn
}

output "output_data_bucket_domain_name" {
  value = aws_s3_bucket.output_data.bucket_domain_name
}

output "output_data_bucket_regional_domain_name" {
  value = aws_s3_bucket.output_data.bucket_regional_domain_name
}

output "output_data_bucket_region" {
  value = data.aws_region.current.name
}

output "glue_job_name" {
  value = aws_glue_job.api_to_s3.id
}

output "glue_job_arn" {
  value = aws_glue_job.api_to_s3.arn
}

output "glue_role_name" {
  value = aws_iam_role.glue.name
}

output "glue_role_arn" {
  value = aws_iam_role.glue.arn
}

output "glue_test_script_s3_uri" {
  value = "s3://${aws_s3_bucket.glue_scripts.bucket}/${aws_s3_object.glue_test_script_zip.key}"
}

output "external_api_endpoint" {
  value = var.external_api_endpoint
}


output "lambda_function_name" {
  description = "Nom de la fonction Lambda"
  value       = aws_lambda_function.api_fetcher.function_name
}

output "lambda_function_arn" {
  description = "ARN de la fonction Lambda"
  value       = aws_lambda_function.api_fetcher.arn
}

output "lambda_zip_s3_uri" {
  description = "URI S3 du zip Lambda"
  value       = "s3://${aws_s3_bucket.scripts.bucket}/lambda/lambda_function.zip"
}