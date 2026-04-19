# --- Data source: latest Ubuntu 24.04 LTS image ---

data "google_compute_image" "ubuntu" {
  family  = var.image_family
  project = var.image_project
}

# --- Local values ---
#
# IP layout (10.10.0.0/20):
#   .2-.3   Bastion nodes
#   .10     Control-plane
#   .20-.21 Workers
#   .30     OpenBao

locals {
  common_labels = {
    managed_by = "terraform"
    env        = var.environment
  }

  instances = merge(
    # --- Bastion nodes (external IP, SSH entry points) ---
    {
      for i, name in var.bastion_nodes : name => {
        zone        = var.zones[i % length(var.zones)]
        role        = "bastion"
        tags        = ["bastion", "ssh", "internal"]
        network_ip  = cidrhost(var.vpc_cidr, 2 + i)
        external_ip = true
      }
    },
    # --- Control-plane (private) ---
    {
      (var.control_node) = {
        zone        = var.zones[0]
        role        = "control-plane"
        tags        = ["control-plane", "ssh", "internal"]
        network_ip  = cidrhost(var.vpc_cidr, 10)
        external_ip = false
      }
    },
    # --- Workers (private) ---
    {
      for i, name in var.worker_nodes : name => {
        zone        = var.zones[i % length(var.zones)]
        role        = "worker"
        tags        = ["worker", "ssh", "internal"]
        network_ip  = cidrhost(var.vpc_cidr, 20 + i)
        external_ip = false
      }
    },
    # --- OpenBao (private) ---
    {
      (var.openbao_node) = {
        zone        = var.zones[1]
        role        = "openbao"
        tags        = ["openbao", "ssh", "internal"]
        network_ip  = cidrhost(var.vpc_cidr, 30)
        external_ip = false
      }
    },
  )
}

# --- Compute instances (bastions + control-plane + workers + openbao) ---

resource "google_compute_instance" "node" {
  for_each = local.instances

  name         = each.key
  machine_type = var.machine_type
  zone         = each.value.zone

  labels = merge(local.common_labels, {
    role = each.value.role
  })

  boot_disk {
    kms_key_self_link = google_kms_crypto_key.disk_encryption.id
    auto_delete       = true

    initialize_params {
      size  = var.disk_size_gb
      type  = var.disk_type
      image = data.google_compute_image.ubuntu.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    network_ip = each.value.network_ip

    dynamic "access_config" {
      for_each = each.value.external_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    ssh-keys = "jollywonka:${var.ssh_public_key}"
  }

  service_account {
    email  = google_service_account.compute.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  tags = each.value.tags

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  depends_on = [
    google_kms_crypto_key_iam_member.compute_encrypter,
    google_kms_crypto_key_iam_member.gce_service_agent_encrypter,
    google_compute_router_nat.nat,
  ]
}
