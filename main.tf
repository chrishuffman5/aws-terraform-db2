# Define the provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region                  = "us-east-1"
  shared_credentials_file = "Users/chris/.aws/credentials"
}

terraform {
  backend "s3" {
    bucket         = "simplistiq-terraform-state"
    key            = "terraform/state/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"
    encrypt        = "true"
  }
}

# Create an S3 bucket
resource "aws_s3_bucket" "example_bucket" {
  bucket = "example-bucket8sl3a" # Replace with your desired bucket name
}

# Create an Athena database
resource "aws_athena_database" "example_database" {
  name     = "example_database" # Replace with your desired database name
  bucket  = aws_s3_bucket.example_bucket.id
}

resource "aws_kms_key" "test" {
  deletion_window_in_days = 7
  description             = "Athena KMS Key"
}

# Create an Athena workgroup
resource "aws_athena_workgroup" "example_workgroup" {
  name        = "example_workgroup" # Replace with your desired workgroup name
  description = "Example Athena Workgroup"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.example_bucket.bucket}/results/" # Replace with your S3 bucket path for storing query results
      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.test.arn
      }
    }
  }
}

# Grant Athena workgroup access to the S3 bucket
resource "aws_s3_bucket_policy" "example_bucket_policy" {
  bucket = aws_s3_bucket.example_bucket.id

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          Service = "athena.amazonaws.com"
        },
        Action    = ["s3:GetObject"],
        Resource  = [
          "${aws_s3_bucket.example_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create a local CSV file
resource "local_file" "example_csv" {
  filename = "example.csv" # Replace with your desired CSV file name
  content  = <<-EOT
    ID, FirstName, LastName, Age, City, State
    1, John, Doe, 30, New York, NY
    2, Alice, Smith, 25, Los Angeles, LA
  EOT
}

# Upload the CSV file to the S3 bucket
resource "aws_s3_bucket_object" "example_csv_object" {
  bucket = aws_s3_bucket.example_bucket.id
  key    = "example.csv" # Replace with the desired path and name within the bucket
  source = local_file.example_csv.filename
}

# Create an Athena named query
resource "aws_athena_named_query" "example_named_query" {
  name             = "example_named_query" # Replace with your desired named query name
  database         = aws_athena_database.example_database.name
  workgroup        = aws_athena_workgroup.example_workgroup.name
  query            = "SELECT * FROM ${aws_athena_database.example_database.name} limit 1;"
}

# Create an AWS Glue Database
resource "aws_glue_catalog_database" "example_glue_database" {
  name = "example_glue_database" # Replace with your desired Glue database name
}

resource "aws_glue_crawler" "example" {
  database_name = "${aws_glue_catalog_database.example_glue_database.name}"
  name          = "example"
  role          = "arn:aws:iam::875137030400:role/service-role/AWSGlueServiceRole-Crawler-Example"

  s3_target {
    path = "s3://${aws_s3_bucket.example_bucket.bucket}/example.csv"
  }
}

# Create an AWS Glue Table
resource "aws_glue_catalog_table" "example_glue_table" {
  name          = "example_glue_table" # Replace with your desired Glue table name
  database_name = aws_glue_catalog_database.example_glue_database.name
  catalog_id    = aws_glue_catalog_database.example_glue_database.catalog_id
  table_type    = "EXTERNAL_TABLE"
  parameters = {
    "classification"    = "csv"
    "skip.header.line.count" = "1"
  }
  storage_descriptor {
    location        = aws_s3_bucket_object.example_csv_object.id
    input_format    = "org.apache.hadoop.mapred.TextInputFormat"
    output_format   = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info {
      name                  = "CsvSerde"
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"
      parameters = {
        "separatorChar" = ","
      }
    }
    columns {
      name = "ID"
      type = "int"
    }
    columns {
      name = "FirstName"
      type = "string"
    }
    columns {
      name = "LastName"
      type = "string"
    }
    columns {
      name = "Age"
      type = "int"
    }
    columns {
      name = "City"
      type = "string"
    }
    columns {
      name = "State"
      type = "string"
    }
  }
}
