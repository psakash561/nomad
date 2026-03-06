terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary region (this is what Nomad Brain will change)
provider "aws" {
  region = var.target_region
}

# Secondary provider for DynamoDB replica region
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Primary provider for DynamoDB global table (Frankfurt)
provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"
}

terraform {
  backend "s3" {
    bucket         = "akash-nomad-terraform-state"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}