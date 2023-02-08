resource "aws_cloudwatch_event_rule" "ecr_scan_event" {
  name          = "${var.prefix}-enhanced-scanning-event"
  description   = "Triggered when image scan was completed."
  tags          = var.tags
  event_pattern = <<EOF
  {
  "detail-type": ["Inspector2 Scan"],
  "source": ["aws.inspector2"]
}
  EOF
  role_arn = aws_iam_role.ecr_scan_role.arn
}

resource "aws_cloudwatch_event_target" "ecr_scan_event_target" {
  rule = aws_cloudwatch_event_rule.ecr_scan_event.name
  arn  = aws_sns_topic.ecr_scan_sns_topic.arn
  input_transformer {
    input_paths    = { "findings" : "$.detail.finding-severity-counts", "repo" : "$.detail.repository-name", "digest" : "$.detail.image-digest", "time" : "$.time", "status" : "$.detail.scan-status", "tags" : "$.detail.image-tags", "account" : "$.account", "region" : "$.region" }
    input_template = <<EOF
"ECR Image scan results: :rotating_light:"
":docker:: <repo>"
":label:: <tags>"
":warning:: <findings>"
":link:: https://${var.aws_region}.console.aws.amazon.com/ecr/repositories/private/<account>/REPLACE_ME/_/image/<digest>/scan-results?region=${var.aws_region}"
EOF
  }
}

resource "aws_cloudwatch_metric_alarm" "ecr_scan_notification_lambda" {
  alarm_name                = "${var.prefix}-notification"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = 1
  metric_name               = "Errors"
  namespace                 = "AWS/Lambda"
  period                    = 60
  statistic                 = "Sum"
  unit                      = "Count"
  threshold                 = 1
  alarm_description         = "This metric monitors the errors into lambda function"
  insufficient_data_actions = []
  ok_actions = []

  dimensions = {
    FunctionName = aws_lambda_function.ecr_scan_notification_lambda.function_name
  }
}

resource "aws_iam_role" "ecr_scan_role" {
  name               = "${var.prefix}-events-role"
  tags               = var.tags
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecr_scan_role_policy" {
  name   = "${var.prefix}-scan-policy"
  role   = aws_iam_role.ecr_scan_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "SNS:*"
      ],
      "Resource": "${aws_sns_topic.ecr_scan_sns_topic.arn}"
    },
    {
      "Effect":"Allow",
      "Action": [
        "lambda:*"
      ],
      "Resource": "${aws_lambda_function.ecr_scan_notification_lambda.arn}"
    }
  ]
}
EOF
}

resource "aws_sns_topic" "ecr_scan_sns_topic" {
  name = "${var.prefix}-scanning"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "ecr_scan_sns_topic_subscription" {
  topic_arn = aws_sns_topic.ecr_scan_sns_topic.id
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ecr_scan_notification_lambda.arn
}

resource "aws_sns_topic_policy" "sns-policy" {
  arn    = aws_sns_topic.ecr_scan_sns_topic.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    actions = [
      "sns:Publish"
    ]
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [
      aws_sns_topic.ecr_scan_sns_topic.arn,
    ]

    sid = "CloudwatchEventsMayPublish"
  }
}

resource "aws_lambda_function" "ecr_scan_notification_lambda" {
  function_name = "${var.prefix}-notification"
  filename      = "${path.module}/slackify.zip"
  role          = aws_iam_role.ecr_scan_notification_lambda_role.arn
  tags          = var.tags
  runtime       = "python3.8"
  handler       = "slackify.lambda_handler"
  depends_on = [data.archive_file.slackify-zip]
  environment {
    variables = {
      SLACK_WEBHOOK = var.slack_webhook
    }
  }
}

resource "aws_iam_role" "ecr_scan_notification_lambda_role" {
  name               = "${var.prefix}-notification-role"
  tags               = var.tags
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecr_scan_notification_lambda_role_policy" {
  name   = "${var.prefix}-notification-policy"
  role   = aws_iam_role.ecr_scan_notification_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"
    },
    {
        "Effect": "Allow",
        "Action": [
            "lambda:InvokeFunction"
        ],
        "Condition": {
            "ArnEquals": {
                "aws:SourceArn":"${aws_cloudwatch_event_rule.ecr_scan_event.arn}"
            }
        },
        "Resource": "${aws_lambda_function.ecr_scan_notification_lambda.arn}"
    }
  ]
}
EOF
}

resource "aws_lambda_permission" "ecr_scan_lambda_permission" {
  statement_id  = "AllowExecutionFromEventBus"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecr_scan_notification_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.ecr_scan_sns_topic.arn
}

data "archive_file" "slackify-zip" {
  type        = "zip"
  source_file = "${path.module}/slackify.py"
  output_path = "${path.module}/slackify.zip"
}
