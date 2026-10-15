terraform {
  required_version = ">= 1.16"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "kube_context" {
  type    = string
  default = "aiops"
}

variable "namespace" {
  type    = string
  default = "pawel"
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

resource "kubernetes_network_policy_v1" "postgres_ingress" {
  metadata {
    name      = "kantyna-postgres-ingress"
    namespace = var.namespace
    labels = {
      "aiops/lab" = "lab04"
    }
  }

  spec {
    policy_types = ["Ingress"]

    pod_selector {
      match_labels = {
        "app.kubernetes.io/name"     = "postgres"
        "app.kubernetes.io/instance" = "kantyna"
      }
    }

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name"     = "orders-api"
            "app.kubernetes.io/instance" = "kantyna"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }
  }
}
