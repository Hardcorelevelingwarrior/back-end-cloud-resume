terraform {
  required_providers{
    aws = {
        
        source = "hashicorp/aws"
        version = "~> 4.61.0"
    }
  }
}
provider "aws" {
  # Configuration options
  region = "us-east-2"
}
//Create aws bucket and assign it as a static website
 resource "aws_s3_bucket" "my-site-dumiv3" {
  bucket = "my-site-dumiv3"
}
resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = "my-site-dumiv3"
  index_document {
    suffix = "index.html"
  }
}
resource "aws_s3_bucket_acl" "acl_public" {
  bucket = "my-site-dumiv3"
  acl = "public-read"
}
resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.my-site-dumiv3.id
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::my-site-dumiv3/*"]
    }
  ]
}
POLICY

}

locals {
  s3_origin_id = "my-site-dumiv3"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "my-site-dumiv3"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.my-site-dumiv3.bucket_regional_domain_name
    origin_id = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }
  enabled = true
  is_ipv6_enabled = true
  comment = "my-cloudfront"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]
     cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      //locations        = ["US", "CA", "GB", "DE"]
    }
  }

}

resource "aws_dynamodb_table" "dynamo_table_for_dumisite" {
  name = "nhuducminh"
  hash_key = "stat"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "stat"
    type = "S"
  }

}

resource "aws_dynamodb_table_item" "name" {
  table_name = aws_dynamodb_table.dynamo_table_for_dumisite.name
  hash_key = aws_dynamodb_table.dynamo_table_for_dumisite.hash_key

  item = <<ITEM
{
  "stat" : {"S" : "view-count"},
  "Quantity" : {"N":"0"}
}
ITEM

}




data "archive_file" "lamda" {
  type = "zip"
  source_file = "lamda.py"
  output_path = "lamda_function_payload.zip"
  
}

resource "aws_lambda_function" "test_lamda" {
  filename = "lamda_function_payload.zip"
  function_name = "View-count"
  role = "arn:aws:iam::682220946551:role/service-role/ducminh-role-2sxxca8z"
  handler = "index.test"

  runtime = "python3.9"
}


resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "serverless_lambda_stage"
  auto_deploy = true

}

resource "aws_apigatewayv2_integration" "test_lamda" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.test_lamda.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "GET"
}

resource "aws_apigatewayv2_route" "test_lamda" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /index"
  target    = "integrations/${aws_apigatewayv2_integration.test_lamda.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lamda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}
