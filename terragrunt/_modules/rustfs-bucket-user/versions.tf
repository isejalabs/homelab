terraform {
  required_providers {
    rustfs = {
      source  = "weinmann-emt/rustfs"
      version = "~> 0.0.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
