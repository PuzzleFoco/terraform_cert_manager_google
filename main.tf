# ---------------------------------------------------------------------------------------------------------------------
# Cert-Manager
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_providers {
    helm = ">= 1.0.0"
  }
}

// Describes the version of CustomResourceDefinition and Cert-Manager Helmchart
locals {
  customResourceDefinition = "0.10"
  certManagerHelmVersion   = "v0.10.0"

  // values_yaml_rendered = templatefile("./${path.module}/values.yaml.tpl", {
  //   resources = "${var.resources}"
  // })
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
    command = "kubectl --context ${var.cluster_name} apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-${local.customResourceDefinition}/deploy/manifests/00-crds.yaml"
  }
  depends_on = [null_resource.get_kubectl]
}

// Creates Namespace for cert-manager. necessary to disable resource validation
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    labels = {
      "certmanager.k8s.io/disable-validation" = "true"
    }
    name = "cert-manager"
  }
  depends_on = [null_resource.install_crds]
}

// Adds jetsteck to helm repo
data "helm_repository" "jetstack" {
  provider = "helm"
  name     = "jetstack"
  url      = "https://charts.jetstack.io"
}

// Install cert-manager via helm in namespace cert-manager
resource "helm_release" "cert-manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  repository = "${data.helm_repository.jetstack.name}"
  chart      = "cert-manager"
  version    = "${local.certManagerHelmVersion}"

  depends_on = ["kubernetes_namespace.cert_manager"]
}

// Creates secret with our client_secret inside. Is used to give cert-manager the permission to make an  acme-challenge to prove let's encrypt
// that we are the owner of our domain
resource "kubernetes_secret" "cert-manager-secret" {
  metadata {
    name      = "secret-google-config"
    namespace = "${kubernetes_namespace.cert_manager.metadata.0.name}"
  }

  data = {
    password = "${var.client_secret}"
  }
}

// Creates a template file with all necessary variables for permission. This template contains a clusterissuer and a certificate
data "template_file" "cert_manager_manifest" {
  template = "${file("${path.module}/cert-manager.yaml")}"

  vars = {
    DOMAIN                     = "${var.root_domain}"
    PROJECT_ID                 = var.project_id
    NAMESPACE                  = "${kubernetes_namespace.cert_manager.metadata.0.name}"
    CERT_NAME                  = "wildcard"
    PASSWORD                   = "password"
    SECRET_NAME                = "${kubernetes_secret.cert-manager-secret.metadata.0.name}"
    EMAIL                      = "${var.lets_encrypt_email}"
  }
}

// Install our cert-manager template
resource "null_resource" "install_k8s_resources" {
  provisioner "local-exec" {
    command = "kubectl --context ${var.cluster_name} apply -f -<<EOL\n${data.template_file.cert_manager_manifest.rendered}\nEOL"
  }
}