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
    delete_default_routes_on_create = true
    auto_create_subnetworks = false
}

resource "google_compute_global_address" "private_service_address" {
  project       = var.project_id
  name          = "private-service-address"
  address_type  = "INTERNAL"
  purpose       = "VPC_PEERING"
  prefix_length = 24
  network       = google_compute_network.vpc-tf.id
}

resource "google_service_networking_connection" "private_service_forwarding_rule" {
  network               = google_compute_network.vpc-tf.name
  service               = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_address.name]
}

resource "google_compute_subnetwork" "webapp" {
  name                    = "webapp"
  ip_cidr_range           = var.webapp_ip
  region                  = var.region
  network                 = google_compute_network.vpc-tf.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "db" {
  name          = "db"
  ip_cidr_range = var.db_ip
  region        = var.region
  network       = google_compute_network.vpc-tf.id
}

resource "google_compute_route" "router" {
  name             = "router"
  dest_range       = var.routerange
  network          = google_compute_network.vpc-tf.id
  next_hop_gateway = var.next_hop
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "dbinstance" {
  project            = var.project_id
  name               = "cloudDB"
  region             = var.region
  database_version   = "MYSQL_5_7"
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    availability_type = "REGIONAL"
    disk_type         = "pd-ssd"
    disk_size         = 100

    ip_configuration {
      ipv4_enabled      = true
      private_network   = google_compute_network.vpc-tf.self_link
    }

    backup_configuration {
      binary_log_enabled = true
      enabled            = true
    }
  }

  depends_on = [
    google_service_networking_connection.private_service_forwarding_rule
  ]
}

resource "google_sql_database" "webapp" {
  name     = "webapp"
  instance = google_sql_database_instance.dbinstance.name
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_sql_user" "webapp" {
  name     = "webapp"
  instance = google_sql_database_instance.dbinstance.name
  password = random_password.password.result
}

resource "google_compute_firewall" "block_ssh_port" {
  name          = "block-ssh-port"
  network       = google_compute_network.vpc-tf.self_link

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_application_port" {
  name          = "allow-application-port"
  network       = google_compute_network.vpc-tf.self_link
  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["application-instance"]
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

  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      echo "DB_DIALECT=mysql" >> /opt/csye6225/.env
      echo "DB_HOST=${google_sql_database_instance.dbinstance.private_ip_address}" >> /opt/csye6225/.env
      echo "DB_USERNAME=webapp" >> /opt/csye6225/.env
      echo "DB_PASSWORD=${google_sql_user.webapp.password}" >> /opt/csye6225/.env
      echo "DB_NAME=webapp" >> /opt/csye6225/.env
      sudo systemctl daemon-reload
      sudo systemctl enable nodeindex.service
      sudo systemctl restart nodeindex.service
    EOF
  }
}
