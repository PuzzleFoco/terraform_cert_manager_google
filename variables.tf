############################################################################
# Created Date: 08.10.2019                                                 #
# Author: Fabius Engel (fabius.engel@msg.group)                            #
# -----                                                                    #
# Last Modified: 23.10.2019 09:29:46                                       #
# Modified By: Michael Süssemilch (michael.suessemilch@msg.group)          #
# -----                                                                    #
# Copyright (c) 2019 msg nexinsure ag                                      #
############################################################################

variable "subscription_id" {}

variable "client_id" {}

variable "client_secret" {}

variable "tenant_id" {}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Azure Kubernetes Cluster"
  type        = string
}

variable "root_domain" {
  type = string
}

variable "dns_zone_resource_group" {
  description = "The name of the resource group for DNS_Zone"
  type        = string
}

variable "lets_encrypt_email" {
  type = string
}

// variable "resources" {
//   description = "The allocated resources for the module"
//   type        = any
// }