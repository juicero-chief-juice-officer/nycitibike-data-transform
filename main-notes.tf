terraform {
  required_version = ">= 1.0"
  backend "gcs" {
    bucket = "z_infra_resources"
  } # Can change from "local" to "gcs" (for google) or "s3" (for aws), if you would like to preserve your tf-state online
  # terraform will not create the bucket, so bucket must be created from CLI/GUI
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

# Generate random brief suffix to ensure service-account names are globally unique.
resource "random_id" "suffix" {
  byte_length = 2
}

provider "google" {
  project = var.project
  region  = var.region
}

provider "google-beta" {
  project = var.project
  region  = var.region
  # alias   = "secret-manager"
}

# provider "google-secret-manager" {
#   project = var.project
#   region  = var.region
# }

data "google_project" "project" {
  project_id = var.project
}

data "google_compute_default_service_account" "default" {
}

output "project_number" {
  value = data.google_project.project.number
}

#enable secret manager API
resource "google_project_service" "secretmanager" {
  provider = google-beta
  service  = "secretmanager.googleapis.com"
}

# Service Account (If not done via command line.)
#  Create accounts, then add roles, then create keys. 
resource "google_service_account" "sa" {
  for_each = var.svc_accts_and_roles

  account_id   = "${each.key}-${random_id.suffix.hex}"
  display_name = "${each.key}-${random_id.suffix.hex}"
  description  = var.svc_accts_and_roles[each.key]["description"]
}

# Loop through roles in each SA's dict/map and apply to SA
resource "google_project_iam_member" "sa-accounts-iam" {
  for_each = local.svc_accts_iam_flat

  project = var.project
  role    = each.value.role_to_apply
  member  = "serviceAccount:${each.value.svc_acct_to_apply_role_to}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
  # service_account_id = "projects/${var.project}/serviceAccounts/${each.value.svc_acct_to_apply_role_to}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
  depends_on = [google_service_account.sa]

}

resource "google_service_account_key" "mykeys" {
  for_each = { for key, value in var.svc_accts_and_roles : key => value if value["create_key"] && key != var.sa_for_dbt_clrun-key }
  # service_account_id = "${google_service_account.sa[each.key]}"
  service_account_id = "projects/${var.project}/serviceAccounts/${each.key}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
  depends_on         = [google_project_iam_member.sa-accounts-iam]
}

resource "google_service_account_key" "key_clrn" {
  # service_account_id = "${google_service_account.sa[each.key]}"
  service_account_id = "projects/${var.project}/serviceAccounts/${var.sa_for_dbt_clrun-key}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
  depends_on         = [google_project_iam_member.sa-accounts-iam]
  key_algorithm      = "KEY_ALG_RSA_2048"
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

# resource "google_service_account_key" "key_clrn_secret_file" {
#   # account_id         = var.sa_for_dbt_clrun
#   service_account_secret_id        = google_service_account.sa[var.sa_for_dbt_clrun-key].id #.email #.service_account.email
#   # secret_id        = "${var.sa_for_dbt_clrun-key}-key_clrn_secret_file"
# }

resource "google_secret_manager_secret" "clrn_secret" {
  # account_id         = var.sa_for_dbt_clrun
  # secret_id        = google_service_account.sa[var.sa_for_dbt_clrun-key].id #.email #.service_account.email
  secret_id = "${var.sa_for_dbt_clrun-key}-key_clrn_secret_file"
  replication {
    automatic = true
  }
  # key_algorithm    = "KEY_ALG_RSA_2048"
  # private_key_type = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

resource "google_secret_manager_secret_version" "my_secret_version" {
  provider    = google-beta
  secret      = google_secret_manager_secret.clrn_secret.secret_id
  secret_data = base64encode(google_service_account_key.key_clrn.private_key)
}

# resource "google_secret_manager_secret" "service_account_key_secret" {
#   # for_each  = var.svc_accts_and_roles
#   # count     = var.svc_accts_and_roles[each.key]["secret_access"] && var.svc_accts_and_roles[each.key]["create_key"] ? 1 : 0 #count tells terraform how many of the resource to create
#   provider  = google-beta                                 #.secret_manager
#   secret_id = google_secret_manager_secret.clrn_secret.id #"${var.sa_for_dbt_clrun-key}-key_clrn_secret_file"
#   #google_secret_manager_secret.key_clrn_secret_file.id #service_account_key_secret.id #"${each.key}-keyfile"
#   secret_data        = base64encode(google_service_account_key.key_clrn.private_key)
#   secret_data_length = length(google_service_account_key.key_clrn.private_key)
#   replication {
#     automatic = true
#   }
# }

# # resource "google_secret_manager_secret_version" "service_account_key_secret_version" {
# #   provider           = google.secret_manager
# #   secret_id          = google_secret_manager_secret.service_account_key_secret.id
# #   secret_data        = base64encode(google_service_account_key.key.private_key)
# #   secret_data_length = length(google_service_account_key.key.private_key)
# # }


# resource "google_secret_manager_secret" "github-token-secret" {
#   provider  = google-beta
#   secret_id = "github-token-secret"
#   replication {
#     automatic = true
#   }
# }

# resource "google_secret_manager_secret_version" "github-token-secret-version" {
#   provider    = google-beta
#   secret      = google_secret_manager_secret.github-token-secret.id
#   secret_data = file(var.github_token_path)
# }



# data "google_iam_policy" "p4sa-secretAccessor" {
#   # for_each = var.svc_accts_and_roles
#   count = var.svc_accts_and_roles[each.key]["secret_access"] ? 1 : 0 #count tells terraform how many of the resource to create

#   provider = google-beta
#   binding {
#     role = "roles/secretmanager.secretAccessor"
#     // Here, 123456789 is the Google Cloud project number for my-project-name.
#     members = ["serviceAccount:service-${project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"]
#   }
# }

# resource "google_secret_manager_secret_iam_policy" "policy" {
#   provider    = google-beta
#   secret_id   = google_secret_manager_secret.github-token-secret.secret_id
#   policy_data = data.google_iam_policy.p4sa-secretAccessor.policy_data
# }

# resource "google_cloudbuildv2_connection" "my-connection" {
#   provider = google-beta
#   location = var.region
#   name     = "my-connection"

#   github_config {
#     app_installation_id = 123123
#     authorizer_credential {
#       oauth_token_secret_version = google_secret_manager_secret_version.github-token-secret-version.id
#     }
#   }
# }

# resource "google_cloudbuildv2_repository" "my-repository" {
#   provider          = google-beta
#   location          = var.region
#   name              = var.cloud_build_repo_name
#   parent_connection = google_cloudbuildv2_connection.my-connection.name
#   remote_uri        = "https://github.com/myuser/myrepo.git"
# }

# resource "google_cloud_build_trigger" "cloud_run_trigger" {
#   name        = "cloud-run-trigger"
#   description = "Trigger for building and deploying Cloud Run service"
#   trigger_template {
#     branch_name = "main"
#     repo_name   = "my-repo"
#     project_id  = "my-project"
#   }
#   build {
#     tag_name        = "gcr.io/my-project/my-image"
#     dockerfile_path = "path/to/Dockerfile"
#     substitutions = {
#       _BRANCH_NAME = "main"
#     }
#   }
# }

# # resource "google_artifact_registry_repository" "my-repo" {
# #   location      = var.region
# #   repository_id = var.registry_repo_name
# #   description   = var.repo_description
# #   format        = var.repo_format
# # }


# # resource "google_compute_resource_policy" "gce_schedule" {
# #   name   = var.gce_policy_name
# #   region = var.region
# #   description = var.gce_policy_desc
# #   instance_schedule_policy {
# #     vm_start_schedule {
# #       schedule = var.gce_policy_sched_start
# #     }
# #     vm_stop_schedule {
# #       schedule = var.gce_policy_sched_stop
# #     }
# #     time_zone = var.gce_policy_timezone
# #   }
# # }

# # resource "google_compute_instance" "default" {
# #   name         = var.gce_inst_name
# #   machine_type = var.gce_machine_type
# #   zone         = var.gce_zone
# #   # resource_policies = [google_compute_resource_policy.gce_schedule.id]
# #   network_interface {
# #     network = "default"
# #     access_config {
# #       network_tier = "STANDARD"
# #     }
# #   }
# #   boot_disk {
# #     initialize_params {
# #       image = var.gce_image
# #       size = var.gce_image_size
# #     }
# #   }

# # Not Functional; Do not Use
# # metadata_startup_script = <<SCRIPT
# # touch install_pt1.sh install_pt2.sh
# # echo "#!/bin/bash
# # # Go to home directory
# # cd ~
# # # You can change what anaconda version you want on the anaconda site
# # #!/bin/bash
# # wget https://repo.anaconda.com/archive/Anaconda3-2023.03-1-Linux-x86_64.sh
# # bash Anaconda3-2023.03-1-Linux-x86_64.sh -b -p ~/anaconda3
# # rm Anaconda3-2023.03-1-Linux-x86_64.sh
# # echo 'export PATH="~/anaconda3/bin:$PATH"' >> ~/.bashrc 
# # # messy workaround for difficulty running source ~/.bashrc from shell script in ubuntu
# # # sourced from askubuntu question 64387
# # eval '$(cat ~/.bashrc | tail -n +10)'
# # conda init
# # conda update conda
# # conda --version" > install_pt1.sh
# # echo "#!/bin/bash
# # sudo apt-get update -y
# # sudo apt-get upgrade -y
# # pip install prefect prefect-gcp
# # prefect cloud login -k <INSERT_API_KEY>
# # echo 'prefect agent start -q default' >> ~/.bashrc" > install_pt2.sh
# # sudo chmod +x install_pt1.sh install_pt2.sh
# # ./install_pt1.sh
# # source ~/.bashrc
# # ./install_pt2.sh
# # source ~/.bashrc
# # SCRIPT

# # service_account {
# #   # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
# #   email  = google_service_account.gce_default.email
# #   scopes = ["cloud-platform","https://www.googleapis.com/auth/compute"]
# # }

# # This is deactivated for now. 
# # Instead we can use gcloud compute instances add-resource-policies


# # # Deactivated pending fix.
# # # Give compute instance start/stop permissions to default GCE SA
# # resource "google_service_account_iam_member" "gce_default_start_stop" {
# #   role               = "roles/compute.Admin"
# #   service_account_id = data.google_compute_default_service_account.default.name
# #   member             = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
# # }

# # scheduling {
# #   preemptible = var.gce_preemptible
# #   automatic_restart = var.gce_auto_restart
# # }


# # }



# # --Created in previous project--
# # Data Lake Bucket
# # no updates needed here; though we removed the _${var.project} as we were confident we wouldn't risk duplicate naming when creating
# # resource "google_storage_bucket" "data-lake-bucket" {
# #   name          = "${var.gcs_bucket_name}"#_${var.project}" # Uses Local variable. Concatenates DL bucket & Project name for unique naming
# #   location      = var.region

# #   # Optional, but recommended settings:
# #   storage_class = var.storage_class
# #   uniform_bucket_level_access = true

# #   versioning {  
# #     enabled     = true
# #   }

# #   lifecycle_rule {
# #     action {
# #       type = "Delete"
# #     }
# #     condition {
# #       age = 30  // days
# #     }
# #   }

# #   force_destroy = true
# # }

# # --Created in previous project--
# # Data Warehouse
# # Ref: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_dataset
# # resource "google_bigquery_dataset" "dataset" {
# #   dataset_id = var.bq_dataset
# #   project    = var.project
# #   location   = var.region
# # }
