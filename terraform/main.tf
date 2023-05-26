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
##################################################################################
# PROVIDERS
##################################################################################

## We use google-beta primarily. 
provider "google" {
  project = var.project
  region  = var.region
}

provider "google-beta" {
  project = var.project
  region  = var.region
  # alias   = "secret-manager"
}

##################################################################################
# DATA/OUTPUTS
##################################################################################

## Information we'll reference over the course of this infrastructure build
data "google_project" "project" {
  project_id = var.project
}

data "google_compute_default_service_account" "default" {
}

# output "project_number" {
#   value = data.google_project.project.number
# }

##################################################################################
# RESOURCES
##################################################################################

## Random Suffix 
### Generate random brief suffix to ensure service-account names are globally unique.
resource "random_id" "suffix" {
  byte_length = 2
}


## enable multiple services 
### note that tf previously had both google_project_service and google_project_service*s*; but services is deprecated
resource "google_project_service" "project" {
  for_each = var.list_apis_to_enable

  provider = google-beta
  service  = each.value
}
##################
## Data Warehouse
##################
### Create Dev BigQuery Instance
# resource "google_bigquery_dataset" "dataset" {
#   project    = var.project
#   dataset_id = "${var.bq_dataset}-dev"
#   location   = var.region
# }

## Create external Tables for BigQuery to pull from
### This cannot be done in dbt, so we do it with terraform

# resource "google_bigquery_dataset" "datasets-dev" {
#   for_each   = var.external_tables_to_create
#   project    = var.project
#   dataset_id = "${each.value.dataset}-dev"
#   location   = var.region
# }

# resource "google_bigquery_dataset" "datasets-prod" {
#   for_each   = var.external_tables_to_create
#   project    = var.project
#   dataset_id = each.value.dataset
#   location   = var.region
# }

resource "google_bigquery_dataset" "nested_datasets" {
  for_each   = var.external_tables_to_create
  dataset_id = each.value.dataset
  location   = var.region
}

resource "google_bigquery_dataset" "nested_datasets_dev" {
  for_each   = var.external_tables_to_create
  dataset_id = "DEV-${each.value.dataset}"
  location   = var.region
}

resource "google_bigquery_table" "external_tables" {
  for_each   = var.external_tables_to_create
  dataset_id = each.value.dataset
  table_id   = each.value.table_name
  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    compression   = "GZIP"
    source_uris   = ["gs://${var.gcs_bucket_name}/${each.value.gcs_path}*.parquet"]
  }
  time_partitioning {
    type  = "DAY"
    field = each.value.partition_field
  }
  depends_on = [google_bigquery_dataset.nested_datasets]
}

resource "google_bigquery_table" "external_tables-dev" {
  for_each = var.external_tables_to_create

  dataset_id = "DEV_${each.value.dataset}"
  table_id   = each.value.table_name
  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    compression   = "GZIP"
    source_uris   = ["gs://${var.gcs_bucket_name}/${each.value.gcs_path}*.parquet"]
  }
  time_partitioning {
    type  = "DAY"
    field = each.value.partition_field
  }
  depends_on = [google_bigquery_dataset.nested_datasets_dev]
}

##################
## Service Account (If not done via command line.)
##################
###  Create accounts, then add roles, then create keys. 
resource "google_service_account" "sa" {
  for_each = var.svc_accts_and_roles

  account_id   = "${each.key}-${random_id.suffix.hex}"
  display_name = "${each.key}-${random_id.suffix.hex}"
  description  = var.svc_accts_and_roles[each.key]["description"]
}

## Permissions for Service Accounts
### Loop through roles in each SA's dict/map and apply to SA
resource "google_project_iam_member" "sa-accounts-iam" {
  for_each = local.svc_accts_iam_flat

  project = var.project
  role    = each.value.role_to_apply
  member  = "serviceAccount:${each.value.svc_acct_to_apply_role_to}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
  # service_account_id = "projects/${var.project}/serviceAccounts/${each.value.svc_acct_to_apply_role_to}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
  depends_on = [google_service_account.sa]

}

## Keys from service accounts
### only created if create_key flag is true, and if it's NOT the github or cloudrun sa
resource "google_service_account_key" "mykeys" {
  for_each = { for key, value in var.svc_accts_and_roles : key => value if value["create_key"] && key != var.sa_for_dbt_clrun }
  # service_account_id = "${google_service_account.sa[each.key]}"
  service_account_id = "projects/${var.project}/serviceAccounts/${each.key}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
  depends_on         = [google_project_iam_member.sa-accounts-iam]
}

### Specific Key for the cloudrun service account
resource "google_service_account_key" "key_clrn" {
  # service_account_id = "${google_service_account.sa[each.key]}"
  service_account_id = "projects/${var.project}/serviceAccounts/${var.sa_for_dbt_clrun}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
  depends_on         = [google_project_iam_member.sa-accounts-iam]
  key_algorithm      = "KEY_ALG_RSA_2048"
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

##################
## Secrets/Secret Manager
##################
### Instantiate the secret for our github token (not strictly necessary as it's a public repo)
resource "google_secret_manager_secret" "github-token-secret" {
  provider  = google-beta
  secret_id = "github-token-secret"
  replication {
    automatic = true
  }
}

### Assign value (version) to the secret with secret data
resource "google_secret_manager_secret_version" "github_token_secret_version" {
  provider    = google-beta
  secret      = google_secret_manager_secret.github-token-secret.id
  secret_data = file(var.github_token_path)
}

### Instantiate the secret for the cloud run service account to reference
resource "google_secret_manager_secret" "clrn_secret" {
  # account_id         = var.sa_for_dbt_clrun
  # secret_id        = google_service_account.sa[var.sa_for_dbt_clrun-key].id #.email #.service_account.email
  secret_id = "${var.sa_for_dbt_clrun}-key-clrn-secret-file"
  replication {
    automatic = true
  }
}

### Assign a value/version to the secret with secret data
resource "google_secret_manager_secret_version" "clrn_secret_version" {
  provider    = google-beta
  secret      = google_secret_manager_secret.clrn_secret.secret_id
  secret_data = base64encode(google_service_account_key.key_clrn.private_key)
  depends_on  = [google_secret_manager_secret.clrn_secret]
}


## Specfic to GitHub secret
### Get the policy data/permissions for a secret accessor under this project
data "google_iam_policy" "p4sa-secretAccessor" {
  #dbt-trnsfrm-sa2
  provider = google-beta
  binding {
    role = "roles/secretmanager.secretAccessor"
    // Here, 123456789 is the Google Cloud project number for my-project-name.
    # members = ["serviceAccount:service-${output.project_number.value}@gcp-sa-cloudbuild.iam.gserviceaccount.com"]
    members = ["serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"]
  }
}

### Assign that policy data/permissions to the gituhb secret
resource "google_secret_manager_secret_iam_policy" "policy" {
  provider    = google-beta
  secret_id   = google_secret_manager_secret.github-token-secret.secret_id
  policy_data = data.google_iam_policy.p4sa-secretAccessor.policy_data
}

##################
## Cloud Build
##################
### Create a connection in cloudbuild that pulls from github 
resource "google_cloudbuildv2_connection" "clbd-gh-connection" {
  provider = google-beta
  location = var.region
  name     = "clbd-gh-connection"

  github_config {
    # app_installation_id = 1363010
    authorizer_credential {
      oauth_token_secret_version = google_secret_manager_secret_version.github_token_secret_version.id
    }
  }
}


resource "null_resource" "check_cloudbuild_state" {
  triggers = {
    connection_id = google_cloudbuildv2_connection.clbd-gh-connection.id
  }
  # until [ $(gcloud cloudbuildv2 connection describe ${self.triggers.connection_id} --format="get(installationState)") == "COMPLETE" ]; do

  provisioner "local-exec" {
    command = <<-EOF
      until [[ $(gcloud alpha builds connections describe ${self.triggers.connection_id} --format="get(installationState)") == "COMPLETE" ]]; do
        echo "waiting for installation to complete..."
        sleep 5
      done
EOF
  }
}

### Create a gcp repo for the github repo to be pulled into
resource "google_cloudbuildv2_repository" "gh-transform-repo" {
  provider          = google-beta
  location          = var.region
  name              = var.cloud_build_repo_name
  parent_connection = google_cloudbuildv2_connection.clbd-gh-connection.name
  remote_uri        = var.github_repo_path
  depends_on        = [null_resource.check_cloudbuild_state]
  # depends_on        = [google_cloudbuildv2_connection.clbd-gh-connection] #despite appearances, this does not work as it doesn't check for state of connection
}

## Create a trigger thatruns cloudbuild anytime an update is made to the gcp repo, which itself is updated based on changes to the main github brand
resource "google_cloudbuild_trigger" "cloud_bld_trigger" {
  name        = "cloud-bld-trigger"
  description = "Trigger for building and deploying Cloud Run service"
  trigger_template {
    branch_name = "main"
    repo_name   = var.cloud_build_repo_name
    project_id  = data.google_project.project.project_id
    # tag_name    = "ghcr.io/dbt-labs/dbt-bigquery"
  }
  build {
    step {
      name = "ghcr.io/dbt-labs/dbt-bigquery"
    }
    substitutions = {
      _BRANCH_NAME = "main"
    }
  }
}
##################
## Cloud Run
##################
### create a cloud run service that pulls the dbt-bigquery image and runs it using permissions contained in the cloud run service account/secret
resource "google_cloud_run_service" "dbt_clrn_service" {
  name     = var.cloud_run_service_name
  location = var.region

  template {
    spec {
      service_account_name = google_service_account.sa[var.sa_for_dbt_clrun].name
      containers {
        image = "ghcr.io/dbt-labs/dbt-bigquery"
        env {
          value_from {
            secret_key_ref {
              key  = google_secret_manager_secret_version.clrn_secret_version.id
              name = google_secret_manager_secret_version.clrn_secret_version.name
            }
          }
        }
      }
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
}

##################
## Cloud Scheduler
##################
### Create a scheduled job that will run dbt every 4 hours. 
resource "google_cloud_scheduler_job" "job" {
  name             = "cld_sched_invoke_build_run"
  description      = "Job to involke Cloud Run dbt every 4 hours a day"
  schedule         = "* */4 * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "320s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "GET"
    uri         = google_cloud_run_service.dbt_clrn_service.status[0].url
    oidc_token {
      service_account_email = data.google_compute_default_service_account.default.email
    }
  }
}


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
