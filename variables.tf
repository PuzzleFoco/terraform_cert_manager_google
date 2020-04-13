variable "project_id" {
  description = "The ID of the cloud project"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Azure Kubernetes Cluster"
  type        = string
}

variable "root_domain" {
  type = string
}

variable "lets_encrypt_email" {
  type = string
}

variable "acme_server_url" {
  description = "The URL of the ACME Server like Lets Encrypt, default is staging Server. Use this for prod: https://acme-v02.api.letsencrypt.org/directory"
  type        = string
  default     = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

variable "location" {
  type = string
}

variable "iam_account" {
  description = "Account E-Mail of the Google Contributor account"
  type = string
}

// variable "resources" {
//   description = "The allocated resources for the module"
//   type        = any
// }