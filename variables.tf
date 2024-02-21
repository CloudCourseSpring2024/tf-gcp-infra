variable "project_id" {
  description = "GCP Project ID"
  type= string
}

variable "region" {
  description = "GCP Region"
  type= string
}

variable "zone" {
  description = "GCP Zone"
  type= string
}

variable "next_hop" {
  description = "Next hop for route"
  type= string
}

variable "imagename" {
  description = "give image name"
  type= string
}

variable "webapp_ip" {
  description = "subnet cidr"
  type= string
}

variable "db_ip" {
  description = "subnet cidr"
  type= string
}

variable "routerange" {
  description = "route range"
  type= string
}

variable "reg" {
  description = "route mode"
  type= string
}