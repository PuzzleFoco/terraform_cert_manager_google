# ---------------------------------------------------------------------------------------------------------------------
# Cert-Manager for GCP
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_providers {
    helm = ">= 1.0.0"
    google = ">= 3.25.0"
  }
}

// Describes the version of CustomResourceDefinition and Cert-Manager Helmchart
locals {
  customResourceDefinition = "v0.15.0"
  certManagerHelmVersion   = "v0.15.0"
}

// Creates Namespace for cert-manager. necessary to disable resource validation
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

// ensures that the right kubeconfig is used local
resource "null_resource" "get_kubectl" {
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.location} --project ${var.project_id}"
  }
}

// Install the CustomResourceDefinition resources separately (requiered for Cert-Manager) 
resource "null_resource" "install_crds" {
  provisioner "local-exec" {
    when    = create
    command = "kubectl apply --cluster gke_${var.project_id}_${var.location}_${var.cluster_name} -f https://github.com/jetstack/cert-manager/releases/download/${local.customResourceDefinition}/cert-manager.crds.yaml"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete --cluster gke_${var.project_id}_${var.location}_${var.cluster_name} -f https://github.com/jetstack/cert-manager/releases/download/${local.customResourceDefinition}/cert-manager.crds.yaml"
  }
  depends_on = [null_resource.get_kubectl]
}

// Creates a JSON File with the credentials of the Google IAM-Account
resource "google_service_account" "certaccount" {
  account_id   = "certaccount"
  project      = "masterthesisproject1234"
}

resource "google_service_account_key" "certkey" {
  service_account_id = google_service_account.certaccount.name
}

resource "kubernetes_secret" "cert-manager-secret" {
  metadata {
    name = "cert-credentials"
    namespace = kubernetes_namespace.cert_manager.metadata.0.name
  }
  data = {
    "key.json" = base64decode(google_service_account_key.certkey.private_key)
  }
}
# resource "null_resource" "create_key_json" {
#   provisioner "local-exec" {
#     when    = create
#     command = "gcloud iam service-accounts keys create ${path.module}/key.json --iam-account ${var.iam_account}"
#   }
#   provisioner "local-exec" {
#     when    = destroy
#     command = "private_key_id=$(jq -r .private_key_id ${path.module}/key.json) && client_email=$(jq -r .client_email ${path.module}/key.json) && gcloud iam service-accounts keys delete $private_key_id --iam-account $client_email --quiet && truncate -s 0 ${path.module}/key.json"
#   }
# }

// Adds jetsteck to helm repo
data "helm_repository" "jetstack" {
  provider = helm
  name     = "jetstack"
  url      = "https://charts.jetstack.io"
}

// Install cert-manager via helm in namespace cert-manager
resource "helm_release" "cert-manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  repository = data.helm_repository.jetstack.url
  chart      = "cert-manager"
  version    = local.certManagerHelmVersion
}

# data "template_file" "cert_secret" {
#   template  = file("${path.module}/key.json")

#   depends_on = [null_resource.create_key_json]
# }

// Creates secret with our client_secret inside. Is used to give cert-manager the permission to make an  acme-challenge to prove let's encrypt
// that we are the owner of our domain
# resource "kubernetes_secret" "cert-manager-secret" {
#   metadata {
#     name      = "secret-google-config"
#     namespace = kubernetes_namespace.cert_manager.metadata.0.name
#   }
#   type = "Opaque"
#   data = {
#     "key.json" = data.template_file.cert_secret.template
#   }
# }

// Creates a template file with all necessary variables for permission. This template contains a clusterissuer and a certificate
data "template_file" "cert_manager_manifest" {
  template = file("${path.module}/cert-manager.yaml")

  vars = {
    DOMAIN                     = var.root_domain
    PROJECT_ID                 = var.project_id
    NAMESPACE                  = kubernetes_namespace.cert_manager.metadata.0.name
    CERT_NAME                  = "wildcard"
    PASSWORD                   = "key.json"
    SECRET_NAME                = kubernetes_secret.cert-manager-secret.metadata.0.name
    EMAIL                      = var.lets_encrypt_email
    ACME_SERVER_URL            = var.acme_server_url
  }
}

// Install our cert-manager template
resource "null_resource" "install_k8s_resources" {
  provisioner "local-exec" {
    when    = create
    command = "kubectl apply --cluster gke_${var.project_id}_${var.location}_${var.cluster_name} -f -<<EOL\n${data.template_file.cert_manager_manifest.rendered}\nEOL"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete --cluster gke_${var.project_id}_${var.location}_${var.cluster_name} -f -<<EOL\n${data.template_file.cert_manager_manifest.rendered}\nEOL"
  }
  depends_on = [null_resource.install_crds]
}