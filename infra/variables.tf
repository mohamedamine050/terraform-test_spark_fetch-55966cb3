variable "aws_region" {
  type        = string
  description = "AWS region for all resources."
}

variable "glue_scripts_bucket_base_name" {
  type        = string
  description = "Base name for the Glue scripts bucket."
  default     = "glue-scripts"
}

variable "output_data_bucket_base_name" {
  type        = string
  description = "Base name for the output data bucket."
  default     = "glue-output-data"
}

variable "external_api_endpoint" {
  type        = string
  description = "External API endpoint consumed by the Glue job."
}
