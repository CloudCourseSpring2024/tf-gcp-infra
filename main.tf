provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  credentials = file("mykey.json")
}

resource "google_compute_network" "vpc-tf" {
  name                    = "vpc-tf"
  auto_create_subnetworks = false
}


resource "google_compute_subnetwork" "webapp" {
  name          = "webapp"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc-tf.self_link
}

resource "google_compute_subnetwork" "db" {
  name          = "db"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc-tf.self_link
}

resource "google_compute_route" "router" {
  name               = "router"
  dest_range         = "0.0.0.0/0"
  network            = google_compute_network.vpc-tf.self_link
  next_hop_gateway   = var.next_hop
}