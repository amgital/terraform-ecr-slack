variable "prefix" {
  type = string
}

variable "slack_webhook" {
  type = string
}

variable "aws_region" {
  type = string
}

data "aws_caller_identity" "current" {}

variable "tags" {
  type = map(string)
}