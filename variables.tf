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