# --- Custom service account for compute instances ---

resource "google_service_account" "compute" {
  account_id   = "develop-platform-vm"
  display_name = "Service account for develop-platform VMs"
}

# --- IAM roles (least-privilege) ---

locals {
  compute_sa_roles = toset([
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/compute.osLogin",
  ])
}

resource "google_project_iam_member" "compute_roles" {
  for_each = local.compute_sa_roles

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.compute.email}"
}
