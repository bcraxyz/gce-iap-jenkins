variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone"
  type        = string
  default     = "us-central1-a"
}

variable "image_name" {
  description = "Compute Engine VM image name"
  type        = string
}

variable "domain_name" {
  description = "Domain name for SSL certificate"
  type        = string
}

variable "iap_user_email" {
  description = "Email address of the user who will access VM via IAP"
  type        = string
}
