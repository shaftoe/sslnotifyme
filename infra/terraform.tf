variable "domain_name" {}
variable "verification_token" {}
variable "dkim1_token" {}
variable "dkim2_token" {}
variable "dkim3_token" {}
variable "ses_bounce_email" {}
variable "aws_account_id" {}
variable "aws_region" {}

variable "aws_cloudfront_enabled" {
  default = false
}

variable "aws_cloudfront_id" {
  default = ""
}

variable "cloudwatch_retention_in_days" {
  default = 180
}

variable "lambda_timeout_in_seconds" {
  default = 30
}

variable "backup_retention_in_days" {
  default = 2
}

provider "aws" {
  region = "${var.aws_region}"
}

data "aws_region" "current" {
  current = true
}

resource "aws_iam_user" "dev-user" {
  name          = "${replace("${var.domain_name}", ".", "")}_dev"
  force_destroy = true
}

data "aws_iam_policy_document" "dev-user-policy" {
  statement {
    actions = [
      "s3:*",
    ]

    resources = [
      "${aws_s3_bucket.frontend.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "dev-user-policy" {
  name   = "${replace("${var.domain_name}", ".", "")}_dev-user"
  path   = "/"
  policy = "${data.aws_iam_policy_document.dev-user-policy.json}"
}

resource "aws_iam_user_policy_attachment" "dev-user-policy-attach" {
  user       = "${aws_iam_user.dev-user.name}"
  policy_arn = "${aws_iam_policy.dev-user-policy.arn}"
}

data "aws_iam_policy_document" "frontend-bucket-policy" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::${replace("${var.domain_name}", ".", "")}-frontend/*",
    ]
  }
}

resource "aws_s3_bucket" "frontend" {
  bucket        = "${replace("${var.domain_name}", ".", "")}-frontend"
  acl           = "public-read"
  policy        = "${data.aws_iam_policy_document.frontend-bucket-policy.json}"
  force_destroy = true

  website {
    index_document = "index.html"
  }
}

###################
# SSL CERTIFICATE #
###################
data "aws_acm_certificate" "ssl-cert" {
  domain   = "${var.domain_name}"
  statuses = ["ISSUED"]
}

###############
# DNS records #
###############
resource "aws_route53_zone" "main" {
  # http://docs.aws.amazon.com/AmazonS3/latest/dev/website-hosting-custom-domain-walkthrough.html
  name = "${var.domain_name}"
}

resource "aws_route53_record" "apex" {
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${var.domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.frontend.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.frontend.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "verification" {
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${var.domain_name}"
  type    = "TXT"
  ttl     = "3600"
  records = ["${var.verification_token}"]
}

resource "aws_route53_record" "dkim1" {
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${var.dkim1_token}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = "3600"
  records = ["${var.dkim1_token}.dkim.amazonses.com"]
}

resource "aws_route53_record" "dkim2" {
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${var.dkim2_token}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = "3600"
  records = ["${var.dkim2_token}.dkim.amazonses.com"]
}

resource "aws_route53_record" "dkim3" {
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${var.dkim3_token}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = "3600"
  records = ["${var.dkim3_token}.dkim.amazonses.com"]
}

# https://docs.aws.amazon.com/ses/latest/DeveloperGuide/receiving-email-mx-record.html
resource "aws_route53_record" "mx" {
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${var.domain_name}"
  type    = "MX"
  ttl     = "3600"
  records = ["10 inbound-smtp.${data.aws_region.current.name}.amazonaws.com"]
}

resource "aws_route53_record" "api-gateway" {
  count   = "${var.aws_cloudfront_enabled ? 1 : 0}"
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "api.${var.domain_name}"
  type    = "CNAME"
  ttl     = "3600"
  records = ["${var.aws_cloudfront_id}.cloudfront.net"]
}

############################
# MESSAGE (EMAIL) DELIVERY #
############################

# https://docs.aws.amazon.com/ses/latest/DeveloperGuide/receiving-email-permissions.html
resource "aws_s3_bucket" "ses-delivery-to-s3" {
  bucket        = "${replace("${var.domain_name}", ".", "")}-ses-inbound-emails"
  policy        = "${data.aws_iam_policy_document.ses-deliver-to-s3-policy.json}"
  force_destroy = true
}

data "aws_iam_policy_document" "ses-deliver-to-s3-policy" {
  statement {
    actions = ["s3:PutObject"]

    resources = ["arn:aws:s3:::${replace("${var.domain_name}", ".", "")}-ses-inbound-emails/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:Referer"
      values   = ["${var.aws_account_id}"]
    }

    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }
  }
}

# https://docs.aws.amazon.com/ses/latest/DeveloperGuide/receiving-email-receipt-rule-set.html
resource "aws_ses_receipt_rule_set" "main" {
  rule_set_name = "${replace("${var.domain_name}", ".", "")}"
}

resource "aws_ses_active_receipt_rule_set" "main" {
  rule_set_name = "${replace("${var.domain_name}", ".", "")}"
  depends_on    = ["aws_ses_receipt_rule_set.main"]
}

resource "aws_ses_receipt_rule" "main" {
  name          = "${replace("${var.domain_name}", ".", "")}-noreply"
  rule_set_name = "${replace("${var.domain_name}", ".", "")}"
  recipients    = ["noreply@${var.domain_name}"]
  enabled       = true
  scan_enabled  = true

  s3_action {
    bucket_name = "${aws_s3_bucket.ses-delivery-to-s3.id}"
    position    = 0
  }
}

resource "aws_ses_receipt_rule" "feedback" {
  name          = "${replace("${var.domain_name}", ".", "")}-feedback"
  rule_set_name = "${replace("${var.domain_name}", ".", "")}"
  recipients    = ["feedback@${var.domain_name}"]
  enabled       = true
  scan_enabled  = true

  s3_action {
    bucket_name = "${aws_s3_bucket.ses-delivery-to-s3.id}"
    position    = 0
  }
}

# https://docs.aws.amazon.com/ses/latest/DeveloperGuide/monitor-sending-activity.html
resource "aws_ses_configuration_set" "ses-configuration-set" {
  name = "${replace("${var.domain_name}", ".", "")}"

  provisioner "local-exec" {
    command = "aws ses set-identity-feedback-forwarding-enabled --identity ${var.ses_bounce_email} --forwarding-enabled"
  }
}

resource "aws_ses_event_destination" "cloudwatch" {
  name                   = "${replace("${var.domain_name}", ".", "")}"
  configuration_set_name = "${aws_ses_configuration_set.ses-configuration-set.name}"
  enabled                = true
  matching_types         = ["send", "reject", "bounce", "complaint", "delivery"]

  cloudwatch_destination = {
    default_value  = "unspecified"
    dimension_name = "emailType"
    value_source   = "messageTag"
  }
}

###########
# STORAGE #
###########
resource "aws_dynamodb_table" "pending_table" {
  name           = "${replace("${var.domain_name}", ".", "")}_pending"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "email"

  attribute = {
    name = "email"
    type = "S"
  }

  # time to live for DynamoDB tables is not supported yet by Terraform
  provisioner "local-exec" {
    command = "${path.module}/add_ttl_to_table.sh ${aws_dynamodb_table.pending_table.name}"
  }
}

resource "aws_dynamodb_table" "users_table" {
  name           = "${replace("${var.domain_name}", ".", "")}_users"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "email"

  attribute = {
    name = "email"
    type = "S"
  }
}

resource "aws_s3_bucket" "backend-backup" {
  bucket = "${replace("${var.domain_name}", ".", "")}-backend-backup"

  lifecycle_rule {
    prefix  = ""
    enabled = true

    expiration {
      days = "${var.backup_retention_in_days}"
    }
  }
}

###########
# LAMBDAS #
###########

data "aws_iam_policy_document" "lambda-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# API Lambda
data "aws_iam_policy_document" "lambda-api-policy" {
  statement {
    actions = ["lambda:InvokeFunction"]

    resources = [
      "${aws_lambda_function.lambda-db.arn}",
      "${aws_lambda_function.lambda-mailer.arn}",
    ]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.lambda-api.arn}"]
  }
}

resource "aws_iam_policy" "lambda-api-policy" {
  name   = "lambda_${replace("${var.domain_name}", ".", "")}_api"
  policy = "${data.aws_iam_policy_document.lambda-api-policy.json}"
}

resource "aws_iam_role" "lambda-api-role" {
  name               = "lambda_${replace("${var.domain_name}", ".", "")}_api"
  assume_role_policy = "${data.aws_iam_policy_document.lambda-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "lambda-api-role-policy-attachment" {
  role       = "lambda_${replace("${var.domain_name}", ".", "")}_api"
  policy_arn = "${aws_iam_policy.lambda-api-policy.arn}"
}

resource "aws_cloudwatch_log_group" "lambda-api" {
  name              = "/aws/lambda/${replace("${var.domain_name}", ".", "")}_api"
  retention_in_days = "${var.cloudwatch_retention_in_days}"
}

# Cron Lambda
data "aws_iam_policy_document" "lambda-cron-policy" {
  statement {
    actions = ["lambda:InvokeFunction"]

    resources = [
      "${aws_lambda_function.lambda-db.arn}",
      "${aws_lambda_function.lambda-checker.arn}",
    ]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.lambda-cron.arn}"]
  }
}

resource "aws_iam_policy" "lambda-cron-policy" {
  name   = "lambda_${replace("${var.domain_name}", ".", "")}_cron"
  policy = "${data.aws_iam_policy_document.lambda-cron-policy.json}"
}

resource "aws_iam_role" "lambda-cron-role" {
  name               = "lambda_${replace("${var.domain_name}", ".", "")}_cron"
  assume_role_policy = "${data.aws_iam_policy_document.lambda-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "lambda-cron-role-policy-attachment" {
  role       = "lambda_${replace("${var.domain_name}", ".", "")}_cron"
  policy_arn = "${aws_iam_policy.lambda-cron-policy.arn}"
}

resource "aws_lambda_function" "lambda-cron" {
  filename         = "${path.module}/build/cron.zip"
  function_name    = "${replace("${var.domain_name}", ".", "")}_cron"
  role             = "${aws_iam_role.lambda-cron-role.arn}"
  handler          = "cron.lambda_main"
  source_code_hash = "${base64sha256(file("${path.module}/build/cron.zip"))}"
  runtime          = "python2.7"
  timeout          = "${var.lambda_timeout_in_seconds}"
}

resource "aws_cloudwatch_log_group" "lambda-cron" {
  name              = "/aws/lambda/${replace("${var.domain_name}", ".", "")}_cron"
  retention_in_days = "${var.cloudwatch_retention_in_days}"
}

resource "aws_cloudwatch_event_rule" "lambda-cronjob-event" {
  # 06:00 UTC every morning
  name                = "${replace("${var.domain_name}", ".", "")}_cronjob"
  schedule_expression = "cron(0 6 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda-cronjob" {
  rule = "${aws_cloudwatch_event_rule.lambda-cronjob-event.name}"
  arn  = "${aws_lambda_function.lambda-cron.arn}"
}

resource "aws_lambda_permission" "allow-cloudwatch-cronjob-event" {
  statement_id  = "allow-cloudwatch-cronjob-event"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda-cron.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.lambda-cronjob-event.arn}"
}

# Database Lambda
data "aws_iam_policy_document" "lambda-db-policy" {
  statement {
    actions = [
      "dynamodb:Scan",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]

    resources = [
      "${aws_dynamodb_table.pending_table.arn}",
      "${aws_dynamodb_table.users_table.arn}",
    ]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.lambda-db.arn}"]
  }

  statement {
    actions = [
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.backend-backup.arn}/*"]
  }
}

resource "aws_iam_policy" "lambda-db-policy" {
  name   = "lambda_${replace("${var.domain_name}", ".", "")}_db"
  policy = "${data.aws_iam_policy_document.lambda-db-policy.json}"
}

resource "aws_iam_role" "lambda-db-role" {
  name               = "lambda_${replace("${var.domain_name}", ".", "")}_db"
  assume_role_policy = "${data.aws_iam_policy_document.lambda-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "lambda-db-role-policy-attachment" {
  role       = "lambda_${replace("${var.domain_name}", ".", "")}_db"
  policy_arn = "${aws_iam_policy.lambda-db-policy.arn}"
}

resource "aws_lambda_function" "lambda-db" {
  filename         = "${path.module}/build/data.zip"
  function_name    = "${replace("${var.domain_name}", ".", "")}_db"
  role             = "${aws_iam_role.lambda-db-role.arn}"
  handler          = "data.lambda_main"
  source_code_hash = "${base64sha256(file("${path.module}/build/data.zip"))}"
  runtime          = "python2.7"
  timeout          = "${var.lambda_timeout_in_seconds}"
}

resource "aws_cloudwatch_log_group" "lambda-db" {
  name              = "/aws/lambda/${replace("${var.domain_name}", ".", "")}_db"
  retention_in_days = "${var.cloudwatch_retention_in_days}"
}

resource "aws_cloudwatch_event_rule" "lambda-db-backup-event" {
  # backup database snapshot to S3 every hour
  name                = "${replace("${var.domain_name}", ".", "")}_db-backup"
  schedule_expression = "cron(0 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda-db-backup" {
  rule = "${aws_cloudwatch_event_rule.lambda-db-backup-event.name}"
  arn  = "${aws_lambda_function.lambda-db.arn}"

  input = <<JSON
{"action": ["backup_tables"]}
JSON
}

resource "aws_lambda_permission" "allow-cloudwatch-db-backup-event" {
  statement_id  = "allow-cloudwatch-db-backup-event"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda-db.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.lambda-db-backup-event.arn}"
}

# Mailer lambda
data "aws_iam_policy_document" "lambda-mailer-policy" {
  statement {
    actions   = ["ses:SendEmail"]
    resources = ["*"]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.lambda-mailer.arn}"]
  }
}

resource "aws_iam_policy" "lambda-mailer-policy" {
  name   = "lambda_${replace("${var.domain_name}", ".", "")}_mailer"
  policy = "${data.aws_iam_policy_document.lambda-mailer-policy.json}"
}

resource "aws_iam_role" "lambda-mailer-role" {
  name               = "lambda_${replace("${var.domain_name}", ".", "")}_mailer"
  assume_role_policy = "${data.aws_iam_policy_document.lambda-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "lambda-mailer-role-policy-attachment" {
  role       = "lambda_${replace("${var.domain_name}", ".", "")}_mailer"
  policy_arn = "${aws_iam_policy.lambda-mailer-policy.arn}"
}

resource "aws_lambda_function" "lambda-mailer" {
  filename         = "${path.module}/build/mailer.zip"
  function_name    = "${replace("${var.domain_name}", ".", "")}_mailer"
  role             = "${aws_iam_role.lambda-mailer-role.arn}"
  handler          = "mailer.lambda_main"
  source_code_hash = "${base64sha256(file("${path.module}/build/mailer.zip"))}"
  runtime          = "python2.7"
  timeout          = "${var.lambda_timeout_in_seconds}"

  environment {
    variables = {
      REPORT_TO_EMAIL = "${var.ses_bounce_email}"
    }
  }
}

resource "aws_cloudwatch_log_group" "lambda-mailer" {
  name              = "/aws/lambda/${replace("${var.domain_name}", ".", "")}_mailer"
  retention_in_days = "${var.cloudwatch_retention_in_days}"
}

# Checker lambda
data "aws_iam_policy_document" "lambda-checker-policy" {
  statement {
    actions = ["lambda:InvokeFunction"]

    resources = [
      "${aws_lambda_function.lambda-mailer.arn}",
    ]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.lambda-checker.arn}"]
  }
}

resource "aws_iam_policy" "lambda-checker-policy" {
  name   = "lambda_${replace("${var.domain_name}", ".", "")}_checker"
  policy = "${data.aws_iam_policy_document.lambda-checker-policy.json}"
}

resource "aws_iam_role" "lambda-checker-role" {
  name               = "lambda_${replace("${var.domain_name}", ".", "")}_checker"
  assume_role_policy = "${data.aws_iam_policy_document.lambda-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "lambda-checker-role-policy-attachment" {
  role       = "lambda_${replace("${var.domain_name}", ".", "")}_checker"
  policy_arn = "${aws_iam_policy.lambda-checker-policy.arn}"
}

resource "aws_lambda_function" "lambda-checker" {
  filename         = "${path.module}/build/checker.zip"
  function_name    = "${replace("${var.domain_name}", ".", "")}_checker"
  role             = "${aws_iam_role.lambda-checker-role.arn}"
  handler          = "checker.lambda_main"
  source_code_hash = "${base64sha256(file("${path.module}/build/checker.zip"))}"
  runtime          = "python2.7"
  timeout          = "${var.lambda_timeout_in_seconds}"
}

resource "aws_cloudwatch_log_group" "lambda-checker" {
  name              = "/aws/lambda/${replace("${var.domain_name}", ".", "")}_checker"
  retention_in_days = "${var.cloudwatch_retention_in_days}"
}

# Reporter Lambda
data "aws_iam_policy_document" "lambda-reporter-policy" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.lambda-reporter.arn}"]
  }

  statement {
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    actions = [
      "logs:FilterLogEvents",
    ]

    resources = [
      "${aws_cloudwatch_log_group.lambda-api.arn}",
      "${aws_cloudwatch_log_group.lambda-checker.arn}",
      "${aws_cloudwatch_log_group.lambda-cron.arn}",
      "${aws_cloudwatch_log_group.lambda-db.arn}",
      "${aws_cloudwatch_log_group.lambda-mailer.arn}",
      "${aws_cloudwatch_log_group.lambda-reporter.arn}",
    ]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.ses-delivery-to-s3.arn}"]
  }

  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = ["${aws_lambda_function.lambda-mailer.arn}"]
  }
}

resource "aws_iam_policy" "lambda-reporter-policy" {
  name   = "lambda_${replace("${var.domain_name}", ".", "")}_reporter"
  policy = "${data.aws_iam_policy_document.lambda-reporter-policy.json}"
}

resource "aws_iam_role" "lambda-reporter-role" {
  name               = "lambda_${replace("${var.domain_name}", ".", "")}_reporter"
  assume_role_policy = "${data.aws_iam_policy_document.lambda-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "lambda-reporter-role-policy-attachment" {
  role       = "lambda_${replace("${var.domain_name}", ".", "")}_reporter"
  policy_arn = "${aws_iam_policy.lambda-reporter-policy.arn}"
}

resource "aws_lambda_function" "lambda-reporter" {
  filename         = "${path.module}/build/reporter.zip"
  function_name    = "${replace("${var.domain_name}", ".", "")}_reporter"
  role             = "${aws_iam_role.lambda-reporter-role.arn}"
  handler          = "reporter.lambda_main"
  source_code_hash = "${base64sha256(file("${path.module}/build/reporter.zip"))}"
  runtime          = "python2.7"
  timeout          = "${var.lambda_timeout_in_seconds}"
}

resource "aws_cloudwatch_log_group" "lambda-reporter" {
  name              = "/aws/lambda/${replace("${var.domain_name}", ".", "")}_reporter"
  retention_in_days = "${var.cloudwatch_retention_in_days}"
}

resource "aws_cloudwatch_event_rule" "lambda-reporter-event" {
  # 06:30 UTC every morning
  name                = "${replace("${var.domain_name}", ".", "")}_reporter"
  schedule_expression = "cron(30 6 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda-reporter" {
  rule = "${aws_cloudwatch_event_rule.lambda-reporter-event.name}"
  arn  = "${aws_lambda_function.lambda-reporter.arn}"
}

resource "aws_lambda_permission" "allow-cloudwatch-reporter-event" {
  statement_id  = "allow-cloudwatch-reporter-event"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda-reporter.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.lambda-reporter-event.arn}"
}

#########################
# FRONTEND (CLOUDFRONT) #
#########################
# Many thanks to https://rbgeek.wordpress.com/2016/04/25/create-aws-cloudfront-distribution-using-terraform/
# for how to setup CloudFront

resource "aws_cloudfront_origin_access_identity" "frontend" {}

# TODO add logging to S3 bucket
resource "aws_cloudfront_distribution" "frontend" {
  origin {
    domain_name = "${aws_s3_bucket.frontend.bucket_domain_name}"
    origin_id   = "${replace("${var.domain_name}", ".", "")}-frontend"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.frontend.cloudfront_access_identity_path}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  retain_on_delete    = true
  aliases             = ["${var.domain_name}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${replace("${var.domain_name}", ".", "")}-frontend"

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = "${data.aws_acm_certificate.ssl-cert.arn}"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1"
  }
}
