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
data "google_service_account" "service_account" {
  account_id = var.account_id
  project    = var.project_id
}

resource "google_service_account_key" "certkey" {
  service_account_id = data.google_service_account.service_account.name
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