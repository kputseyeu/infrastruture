# --- General ---

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-west3"
}

variable "zones" {
  description = "List of GCP zones for instance distribution"
  type        = list(string)
  default     = ["europe-west3-a", "europe-west3-b", "europe-west3-c"]
}

variable "environment" {
  description = "Environment label (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

# --- Network ---

variable "vpc_cidr" {
  description = "CIDR range for the VPC subnet"
  type        = string
  default     = "10.10.0.0/20"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR ranges allowed for SSH access (must be explicitly set)"
  type        = list(string)
}

# --- Compute ---

variable "machine_type" {
  description = "GCE machine type for all instances"
  type        = string
  default     = "e2-medium"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 40
}

variable "disk_type" {
  description = "Boot disk type (pd-ssd, pd-standard, pd-balanced)"
  type        = string
  default     = "pd-ssd"
}

variable "image_family" {
  description = "Image family for boot disk"
  type        = string
  default     = "ubuntu-2404-lts-amd64"
}

variable "image_project" {
  description = "Project that owns the image"
  type        = string
  default     = "ubuntu-os-cloud"
}

# --- KMS ---

variable "kms_keyring_name" {
  description = "Name of the KMS keyring"
  type        = string
  default     = "disk-encryption-keyring"
}

variable "kms_key_name" {
  description = "Name of the KMS crypto key for disk encryption"
  type        = string
  default     = "disk-encryption-key"
}

variable "kms_k8s_key_name" {
  description = "Name of the KMS crypto key for Kubernetes secrets encryption"
  type        = string
  default     = "k8s-secrets-encryption-key"
}

# --- Instance naming ---

variable "control_node" {
  description = "Name for the control-plane node"
  type        = string
  default     = "control-01"
}

variable "worker_nodes" {
  description = "Names for the worker nodes"
  type        = list(string)
  default     = ["worker-01", "worker-02"]
}

variable "openbao_node" {
  description = "Name for the OpenBao (secrets manager) node"
  type        = string
  default     = "openbao-01"
}

variable "bastion_nodes" {
  description = "Names for the bastion (jump) nodes"
  type        = list(string)
  default     = ["bastion-01", "bastion-02"]
}
