# --- KMS Keyring ---

resource "google_kms_key_ring" "disk_encryption" {
  name     = "${var.kms_keyring_name}-v3"
  location = var.region
}

# --- KMS Crypto Key ---

resource "google_kms_crypto_key" "disk_encryption" {
  name     = var.kms_key_name
  key_ring = google_kms_key_ring.disk_encryption.id

  purpose = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }
}

# --- KMS Crypto Key for Kubernetes Secrets Encryption ---

resource "google_kms_crypto_key" "k8s_secrets" {
  name     = var.kms_k8s_key_name
  key_ring = google_kms_key_ring.disk_encryption.id

  purpose = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }
}

# --- IAM: Grant custom compute SA access to disk encryption key ---

resource "google_kms_crypto_key_iam_member" "compute_encrypter" {
  crypto_key_id = google_kms_crypto_key.disk_encryption.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.compute.email}"
}

# --- IAM: Grant GCE Service Agent access to disk encryption key ---

data "google_project" "project" {}

resource "google_kms_crypto_key_iam_member" "gce_service_agent_encrypter" {
  crypto_key_id = google_kms_crypto_key.disk_encryption.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@compute-system.iam.gserviceaccount.com"
}

# --- IAM: Grant control-plane SA access to K8s secrets KMS key ---

resource "google_kms_crypto_key_iam_member" "k8s_secrets_encrypter" {
  crypto_key_id = google_kms_crypto_key.k8s_secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.compute.email}"
}
