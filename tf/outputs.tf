# --- Instances ---

output "instances" {
  description = "All compute instance details"
  value = {
    for k, v in google_compute_instance.node : k => {
      name        = v.name
      zone        = v.zone
      role        = v.labels["role"]
      internal_ip = v.network_interface[0].network_ip
      external_ip = length(v.network_interface[0].access_config) > 0 ? v.network_interface[0].access_config[0].nat_ip : null
    }
  }
}

# --- Bastion hosts (for quick SSH access) ---

output "bastion_hosts" {
  description = "Bastion node external IPs for SSH access"
  value = {
    for k, v in google_compute_instance.node : k => {
      external_ip = v.network_interface[0].access_config[0].nat_ip
      zone        = v.zone
    }
    if v.labels["role"] == "bastion"
  }
}

# --- KMS ---

output "kms_crypto_key_id" {
  value = google_kms_crypto_key.disk_encryption.id
}

output "kms_k8s_crypto_key_id" {
  description = "Resource ID of the KMS crypto key used for Kubernetes secrets encryption"
  value       = google_kms_crypto_key.k8s_secrets.id
}

# --- Network ---

output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "subnet_id" {
  value = google_compute_subnetwork.subnet.id
}
