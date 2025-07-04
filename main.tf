# Configure the Google Cloud provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.40"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required Google Cloud APIs
resource "google_project_service" "enabled_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "oslogin.googleapis.com",
    "iap.googleapis.com",
    "certificatemanager.googleapis.com"
  ])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# Set up custom network, subnet and firewall rules
resource "google_compute_network" "mautic_network" {
  name                    = "mautic-network"
  auto_create_subnetworks = false

  depends_on              = [google_project_service.enabled_apis]
}

resource "google_compute_subnetwork" "mautic_subnet" {
  name          = "mautic-subnet"
  ip_cidr_range = "10.140.1.0/24"
  network       = google_compute_network.mautic_network.id
  region        = var.region
}

resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.mautic_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["mautic-vm"]
}

# Create custom service account and IAM bindings
resource "google_service_account" "mautic_sa" {
  account_id   = "mautic-vm-sa"
  display_name = "Mautic VM Service Account"
  
  depends_on   = [google_project_service.enabled_apis]
}

resource "google_project_iam_member" "mautic_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.mautic_sa.email}"
}

resource "google_project_iam_member" "mautic_sa_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.mautic_sa.email}"
}

# Create Compute instance 
resource "google_compute_instance" "mautic_vm" {
  name         = "mautic-vm"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "bitnami-mautic"
    }
  }

  network_interface {
    network    = google_compute_network.mautic_network.id
    subnetwork = google_compute_subnetwork.mautic_subnet.id
    access_config      = [] # disables public IP
  }

  service_account {
    email  = google_service_account.mautic_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create unmanaged instance group
resource "google_compute_instance_group" "mautic_uig" {
  name        = "mautic-ig"
  zone        = var.zone
  instances   = [google_compute_instance.mautic_vm.id]
  named_port {
    name = "http"
    port = 80
  }
  named_port {
    name = "https"
    port = 443
  }
}

# Create HTTPS Load Balancer resources
resource "google_compute_health_check" "mautic_hc" {
  name               = "mautic-health-check"
  check_interval_sec = 10
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 3
  http_health_check {
    port = 80
    request_path = "/"
  }
}

resource "google_compute_backend_service" "mautic_backend" {
  name                            = "mautic-backend"
  port_name                       = "http"
  protocol                        = "HTTP"
  load_balancing_scheme           = "EXTERNAL"
  timeout_sec                     = 30
  health_checks                   = [google_compute_health_check.mautic_hc.id]
  backend {
    group = google_compute_instance_group.mautic_uig.id
  }
}

resource "google_compute_url_map" "mautic_url_map" {
  name            = "mautic-url-map"
  default_service = google_compute_backend_service.mautic_backend.id
}

resource "google_compute_url_map" "mautic_redirect_map" {
  name            = "mautic-redirect-map"
  default_service = google_compute_backend_service.mautic_backend.id
  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}

resource "google_compute_managed_ssl_certificate" "mautic_cert" {
  name = "mautic-cert"
  managed {
    domains = [var.domain_name]
  }
}

resource "google_compute_target_https_proxy" "mautic_https_proxy" {
  name             = "mautic-https-proxy"
  url_map          = google_compute_url_map.mautic_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.mautic_cert.id]
}

resource "google_compute_target_http_proxy" "mautic_http_proxy" {
  name    = "mautic-http-proxy"
  url_map = google_compute_url_map.mautic_redirect_map.id
}

resource "google_compute_global_forwarding_rule" "mautic_https_forwarding_rule" {
  name                  = "https-forwarding-rule"
  target                = google_compute_target_https_proxy.mautic_https_proxy.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
}
