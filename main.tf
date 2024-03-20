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
  credentials = file(var.mykeystored)
}
data "google_compute_instance" "assign6_instance" {
  name = google_compute_instance.web_instance.name
  zone = var.zone
}

resource "google_dns_record_set" "spring2024Cloud" {
  name         = "spring2024cc.me."
  type         = "A"
  ttl          = 300 # Time to Live (TTL) in seconds
  managed_zone = "spring2024cc"
  
  rrdatas = [
    data.google_compute_instance.assign6_instance.network_interface[0].access_config[0].nat_ip,
  ]
}

resource "google_service_account" "service_account_vm" {
  account_id   = "my-service-account-vm"
  display_name = "My Service Account for vm"
}

# Bind IAM roles to the service account
resource "google_project_iam_binding" "service_account_logging_admin" {
  project = var.project_id
  role    = "roles/logging.admin"
  members = ["serviceAccount:${google_service_account.service_account_vm.email}"]
}

resource "google_project_iam_binding" "service_account_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  members = ["serviceAccount:${google_service_account.service_account_vm.email}"]
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

resource "google_sql_database_instance" "instance" {
  project            = var.project_id
  name               = "cloud-database-instance"
  region             = var.region
  database_version   = "MYSQL_5_7"
  deletion_protection = false
  
  settings {
    tier              = "db-f1-micro"
    availability_type = "REGIONAL"
    disk_type         = "pd-ssd"
    disk_size         = 100

    ip_configuration {
      ipv4_enabled      = false
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
  instance = google_sql_database_instance.instance.name
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_sql_user" "webapp" {
  name     = "webapp"
  instance = google_sql_database_instance.instance.name
  password = random_password.password.result
}

# resource "google_compute_firewall" "block_ssh_port" {
#   name          = "block-ssh-port"
#   network       = google_compute_network.vpc-tf.self_link

#   deny {
#     protocol = "tcp"
#     ports    = ["22"]
#   }

#   source_ranges = ["0.0.0.0/0"]
# }

resource "google_compute_firewall" "allow_application_port" {
  name          = "allow-application-port"
  network       = google_compute_network.vpc-tf.self_link
  allow {
    protocol = "tcp"
    ports    = ["3000","22"]
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

  service_account {
    email  = google_service_account.service_account_vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  network_interface {
    subnetwork = google_compute_subnetwork.webapp.self_link
    access_config {}
  }

  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      mkdir -p /opt/csye6225
      chown csye6225:csye6225 /opt/csye6225

      cat <<-EOL > /opt/csye6225/.env
      DB_DIALECT=mysql
      DB_HOST=${google_sql_database_instance.instance.private_ip_address}
      DB_PORT=3306
      DB_USERNAME=webapp
      DB_PASSWORD=${google_sql_user.webapp.password}
      DB_NAME=webapp
      EOL
      
      cd
      sudo systemctl daemon-reload
      sudo systemctl enable nodeindex.service
      sudo systemctl restart nodeindex.service
      EOF
    }
    depends_on = [google_sql_database_instance.instance, google_sql_user.webapp]
}