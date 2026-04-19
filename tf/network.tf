# --- VPC ---

resource "google_compute_network" "vpc" {
  name                    = "develop-platform-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# --- Subnet ---

resource "google_compute_subnetwork" "subnet" {
  name                       = "develop-platform-subnet"
  region                     = var.region
  network                    = google_compute_network.vpc.id
  ip_cidr_range              = var.vpc_cidr
  private_ip_google_access   = true
  private_ipv6_google_access = "ENABLE_GOOGLE_ACCESS"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# --- Cloud Router (required for Cloud NAT) ---

resource "google_compute_router" "router" {
  name    = "develop-platform-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# --- Cloud NAT (outbound internet for private nodes) ---

resource "google_compute_router_nat" "nat" {
  name                               = "develop-platform-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ============================================================================
# Firewall Rules
# ============================================================================

# --- Firewall: External SSH to Bastion only ---

resource "google_compute_firewall" "ssh_bastion" {
  name    = "allow-ssh-bastion"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = ["bastion"]
}

# --- Firewall: SSH from Bastion to internal nodes ---

resource "google_compute_firewall" "ssh_internal" {
  name    = "allow-ssh-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = ["bastion"]
  target_tags = ["ssh"]
}

# --- Firewall: Internal (all node-to-node traffic) ---

resource "google_compute_firewall" "internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_cidr]
  target_tags   = ["internal"]
}

# --- Firewall: Kubernetes API Server (6443) ---

resource "google_compute_firewall" "k8s_api" {
  name    = "allow-k8s-api"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_tags = ["control-plane", "worker", "bastion"]
  target_tags = ["control-plane"]
}

# --- Firewall: etcd cluster (2379-2380) ---

resource "google_compute_firewall" "k8s_etcd" {
  name    = "allow-k8s-etcd"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["2379-2380"]
  }

  source_tags = ["control-plane"]
  target_tags = ["control-plane"]
}

# --- Firewall: Kubelet API (10250) ---

resource "google_compute_firewall" "k8s_kubelet" {
  name    = "allow-k8s-kubelet"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["10250"]
  }

  source_tags = ["control-plane", "worker"]
  target_tags = ["control-plane", "worker"]
}

# --- Firewall: kube-scheduler (10259) & kube-controller-manager (10257) ---

resource "google_compute_firewall" "k8s_control_components" {
  name    = "allow-k8s-control-components"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["10257", "10259"]
  }

  source_tags = ["control-plane"]
  target_tags = ["control-plane"]
}

# --- Firewall: kube-proxy health check (10256) ---

resource "google_compute_firewall" "k8s_proxy" {
  name    = "allow-k8s-proxy"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["10256"]
  }

  source_tags = ["control-plane", "worker"]
  target_tags = ["worker"]
}

# --- Firewall: NodePort services (30000-32767) ---

resource "google_compute_firewall" "k8s_nodeport" {
  name    = "allow-k8s-nodeport"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }

  source_tags = ["control-plane", "worker"]
  target_tags = ["worker"]
}

# --- Firewall: Calico networking (BGP, Typha, VXLAN) ---

resource "google_compute_firewall" "calico" {
  name    = "allow-calico"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["179", "5473"]
  }

  allow {
    protocol = "udp"
    ports    = ["4789"]
  }

  source_tags = ["control-plane", "worker"]
  target_tags = ["control-plane", "worker"]
}

# --- Firewall: Calico IP-in-IP encapsulation ---

resource "google_compute_firewall" "calico_ipip" {
  name    = "allow-calico-ipip"
  network = google_compute_network.vpc.name

  allow {
    protocol = "4"
  }

  source_tags = ["control-plane", "worker"]
  target_tags = ["control-plane", "worker"]
}

# --- Firewall: OpenBao API (8200) ---

resource "google_compute_firewall" "openbao" {
  name    = "allow-openbao"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8200"]
  }

  source_tags = ["control-plane", "worker", "bastion"]
  target_tags = ["openbao"]
}
