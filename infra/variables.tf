variable "project_name" {
  description = "Prefix used for every resource name."
  type        = string
  default     = "ask-my-notes"
}

variable "region" {
  description = "AWS region. us-east-1 has the widest Bedrock model choice."
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email that receives budget alerts. You must confirm the AWS email."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly spend that triggers alerts."
  type        = string
  default     = "2"
}
