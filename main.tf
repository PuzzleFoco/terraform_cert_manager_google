# ---------------------------------------------------------------------------------------------------------------------
# Cert-Manager
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_providers {
    helm = ">= 1.0.0"
    k8s  = ">= 0.7.6"
  }
}

// Describes the version of CustomResourceDefinition and Cert-Manager Helmchart
locals {
  customResourceDefinition = "v0.14.1"
  certManagerHelmVersion   = "v0.14.1"

  // values_yaml_rendered = templatefile("./${path.module}/values.yaml.tpl", {
  //   resources = "${var.resources}"
  // })
}

// Creates Namespace for cert-manager. necessary to disable resource validation
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    labels = {
      "certmanager.k8s.io/disable-validation" = "true"
    }
    name = "cert-manager"
  }
}

// ensures that the right kubeconfig is used local
resource "null_resource" "get_kubectl" {
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.location} --project ${var.project_id}"
  }
  depends_on = [kubernetes_namespace.cert_manager]
}

data "template_file" "install_crds" {
  template = "https://github.com/jetstack/cert-manager/releases/download/${local.customResourceDefinition}/cert-manager.yaml"
}

resource "k8s_manifest" "cert_manager_crd" {
  content = "${data.template_file.install_crds.rendered}"

  depends_on = [null_resource.get_kubectl]
}

// // Install the CustomResourceDefinition resources separately (requiered for Cert-Manager) 
// resource "null_resource" "install_crds" {
//   provisioner "local-exec" {
//     command = "kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/${local.customResourceDefinition}/cert-manager.yaml"
//   }
//   depends_on = [null_resource.get_kubectl]
// }

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

// resource "null_resource" "create_key_json" {
//   provisioner "local-exec" {
//     command = "gcloud iam service-accounts keys create ${path.module}/key.json --iam-account ${var.iam_account}"
//   }
//   depends_on = [null_resource.get_kubectl]
// }

data "template_file" "cert_secret" {
  template  = "${file("${path.module}/key.json")}"

  depends_on = [k8s_manifest.cert_manager_crd]
}

// Creates secret with our client_secret inside. Is used to give cert-manager the permission to make an  acme-challenge to prove let's encrypt
// that we are the owner of our domain
resource "kubernetes_secret" "cert-manager-secret" {
  metadata {
    name      = "secret-google-config"
    namespace = "${kubernetes_namespace.cert_manager.metadata.0.name}"
  }
  type = "Opaque"
  data = {
    "key.json" = data.template_file.cert_secret.template
  }
}

// Creates a template file with all necessary variables for permission. This template contains a clusterissuer and a certificate
data "template_file" "cert_manager_manifest" {
  template = "${file("${path.module}/cert-manager.yaml")}"

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

resource "k8s_manifest" "install_k8s_resources" {
  content = "${data.template_file.cert_manager_manifest.rendered}"

  depends_on = [kubernetes_secret.cert-manager-secret]
}

// Install our cert-manager template
// resource "null_resource" "install_k8s_resources" {
//   provisioner "local-exec" {
//     command = "kubectl apply -f -<<EOL\n${data.template_file.cert_manager_manifest.rendered}\nEOL"
//   }
//   depends_on = [kubernetes_secret.cert-manager-secret]
// }