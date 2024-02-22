terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.16.0"
    }
  }
}

provider "google" {
  project     = var.project_id
  region      = var.region
  zone        = var.zone
  credentials = file("mykey.json")
}

resource "google_compute_network" "vpc-tf" {
  name                    = "vpc-tf"
  routing_mode            = var.reg
  auto_create_subnetworks = false
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "webapp" {
  name          = "webapp"
  ip_cidr_range = var.webapp_ip
  region        = var.region
  network       = google_compute_network.vpc-tf.self_link
}

resource "google_compute_subnetwork" "db" {
  name          = "db"
  ip_cidr_range = var.db_ip
  region        = var.region
  network       = google_compute_network.vpc-tf.self_link
}
resource "google_compute_route" "router" {
  name             = "router"
  dest_range       = var.routerange
  network          = google_compute_network.vpc-tf.self_link
  next_hop_gateway = var.next_hop
}

resource "google_compute_instance" "web_instance" {
  name         = "web-instance"
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["application-instance"]

  boot_disk {
    initialize_params {
      image = var.imagename
      type  = "pd-balanced"
      size  = 100
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.webapp.self_link
    access_config {}
  }
}

resource "google_compute_firewall" "block_ssh_port" {
  name    = "block-ssh-port"
  network = google_compute_network.vpc-tf.self_link

  deny {
    protocol = "tcp"
    ports    = ["22"]  # SSH port
  }

  source_ranges = ["0.0.0.0/0"]  # Allow traffic from any source
}

resource "google_compute_firewall" "allow_application_port" {
  name    = "allow-application-port"
  network = google_compute_network.vpc-tf.self_link

  allow {
    protocol = "tcp"
    ports    = ["3000"]  
  }

  source_ranges = ["0.0.0.0/0"]  # Allow traffic from any source
  target_tags   = ["application-instance"]  # Ensure that the target tag matches the instance tag
}
