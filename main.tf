provider "google" {
  project = var.project_id
  region = var.region
  zone = var.zone
}

locals {
  instance_name = format("%s-%s", var.instance_name, substr(md5(module.gce-container.container.image), 0, 8))
}

module "gce-container" {
  source = "terraform-google-modules/container-vm/google"

  container = {
    image = var.image

    env = [
      {
        name  = "EULA"
        value = "TRUE"
      },
      {
        name  = "MEMORY"
        value = "2G"
      },
      {
        name  = "MODE"
        value = "creative"
      },
      {
        name  = "SERVER_NAME"
        value = "Hexagon"
      },
      {
        name  = "TZ"
        value = "Europe/Stockholm"
      },
      {
        name  = "OPS"
        value = "Ossyman11,Guzzim0nster"
      },

    ]

    # Declare volumes to be mounted
    # This is similar to how Docker volumes are mounted
    volumeMounts = [
      {
        mountPath = "/data"
        name      = "data-disk-0"
        readOnly  = false
      },
    ]
  }

  # Declare the volumes
  volumes = [
    {
      name = "data-disk-0"

      gcePersistentDisk = {
        pdName = "data-disk-0"
        fsType = "ext4"
      }
    },
  ]

  restart_policy = var.restart_policy
}

resource "google_compute_disk" "pd" {
  project = var.project_id
  name    = "${local.instance_name}-data-disk"
  type    = "pd-ssd"
  zone    = var.zone
  size    = var.disk_size
}

resource "google_compute_instance" "vm" {
  project      = var.project_id
  name         = local.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = module.gce-container.source_image
    }
  }

  attached_disk {
    source      = google_compute_disk.pd.self_link
    device_name = "data-disk-0"
    mode        = "READ_WRITE"
  }

  network_interface {
    subnetwork_project = var.subnetwork_project
    subnetwork         = var.subnetwork
    access_config {}
  }

  metadata = merge(var.additional_metadata, { "gce-container-declaration" = module.gce-container.metadata_value })

  labels = {
    container-vm = module.gce-container.vm_container_label
  }

  tags = ["container-vm-example", "container-vm-test-disk-instance"]

  service_account {
    email = var.client_email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}

resource "google_compute_firewall" "tcp-access" {
  name    = "${local.instance_name}-tcp"
  project = var.project_id
  network = var.subnetwork

  allow {
    protocol = "tcp"
    ports    = [var.image_port]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["container-vm-test-disk-instance"]
}
