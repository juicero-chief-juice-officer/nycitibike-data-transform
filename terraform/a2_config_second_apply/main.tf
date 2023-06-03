terraform {
  required_version = ">= 1.0"
  backend "gcs" {
    bucket = "z_infra_resources"
  } # Can change from "local" to "gcs" (for google) or "s3" (for aws), if you would like to preserve your tf-state online
  # terraform will not create the bucket, so bucket must be created from CLI/GUI
  required_providers {
    google-beta = ">=3.8"
    google = {
      version = "~> 4.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.9.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
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
# provider "github" {
#   token = var.github_token_path # or `GITHUB_TOKEN`
# }
provider "google-beta" {
  project = var.project
  region  = var.region
  # alias   = "secret-manager"
}

provider "null" {
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

data "terraform_remote_state" "config1" {
  backend = "gcs"
  config = {
    bucket = "z_infra_resources01"
    # prefix = "terraform/state" #(only use this if you have also configured a prefix path setting up your backend)
  }
}


##################################################################################
# RESOURCES
##################################################################################



# There are multiple ways of buildning a timer/sleep resource
# This is more complex than the standard "time provider" but an instructional example of local-exec
resource "null_resource" "stall_30_seconds" {
  # for_each = toset(var.list_apis_to_enable)

  # triggers = {
  #   svc_id = google_project_service.project[each.key].id
  # }
  provisioner "local-exec" {
    command = <<-EOF
      sleep 30
EOF
  }
}


# resource "null_resource" "check_cloudbuild_state" {
#   triggers = {
#     connection_id = google_cloudbuildv2_connection.clbd_gh_connection.id
#   }
#   provisioner "local-exec" {
#     # the [[]] is needed to ask for a new test each time, rather than using the same test again and again
#     command = <<-EOF
#       until [[ $(gcloud alpha builds connections describe ${self.triggers.connection_id} --format="get(installationState.stage)") == "COMPLETE" ]]; do
#         echo "waiting for installation to complete..."
#         sleep 5
#       done
# EOF
#   }
# }


resource "google_artifact_registry_repository" "cb_ar_repo" {
  provider = google-beta
  location = var.region
  # repository_id = "gcr.io"
  repository_id = var.cloud_build_repo_name
  description   = var.repo_description
  format        = var.repo_format
}


##################
## Cloud Build
##################
## Create a connection in cloudbuild that pulls from github 
resource "google_cloudbuildv2_connection" "clbd_gh_connection" {
  ### As you're troubleshooting other things, this may return Error: `this update would change the connection's installation state from COMPLETE to PENDING_INSTALL_APP`
  ### You can elither delete at console.cloud.google.com/cloud-build/repositories/2nd-gen  or comment out.
  provider = google-beta
  location = var.region
  name     = "clbd_gh_connection"
  github_config {
    app_installation_id = 37951852
    authorizer_credential {
      oauth_token_secret_version = data.terraform_remote_state.config1.outputs.github_secret_id
    }
  }
  # depends_on = [null_resource.stall_30_seconds]
}

## Create a gcp repo for the github repo to be pulled into
resource "google_cloudbuildv2_repository" "gh_transform_repo" {
  provider = google-beta
  # location = "gcr.io/${data.google_project.project.project_id}/${var.cloud_build_repo_name}"
  # gcr.io/sbh-nycitibike-pipeline-main/sbh-nycitibike-transform-cb-repogh-usc1-p01
  location          = var.region
  name              = var.cloud_build_repo_name
  parent_connection = google_cloudbuildv2_connection.clbd_gh_connection.name
  remote_uri        = var.github_repo_path
  # depends_on        = [null_resource.check_cloudbuild_state]
  # depends_on        = [google_cloudbuildv2_connection.clbd-gh-connection] #despite appearances, this does not work as it doesn't check for *state* of connection
}

# resource "google_cloudbuild_trigger" "cloud_bld_trigger2" {
#   name        = "cloud-bld-trigger2"
#   description = "Trigger specifying filename and repository_event_config"
#   provider    = google-beta
#   location    = var.region
#   filename    = "Dockerfile"
#   repository_event_config {
#     repository = google_cloudbuildv2_repository.gh_transform_repo.id #"sbh-nycitibike-transform-cb-repogh-usc1-p01"
#     push { branch = "^main$" }
#   }
# }

# resource "google_cloudbuild_trigger" "cloud_bld_trigger5" {
#   name        = "cloud-bld-trigger5"
#   description = "Trigger specifying filename and trigger_template"
#   provider    = google-beta
#   location    = var.region
#   filename    = "Dockerfile"
#   trigger_template {
#     repo_name   = google_cloudbuildv2_repository.gh_transform_repo.name
#     project_id  = data.google_project.project.project_id
#     branch_name = "main"
#   }
# }
# resource "google_cloudbuild_trigger" "cloud_bld_trigger6" {
#   name        = "cloud-bld-trigger6"
#   description = "Trigger specifying filename and github"
#   provider    = google-beta
#   location    = var.region
#   filename    = "Dockerfile"
#   github {
#     owner = "juicero-chief-juice-officer"
#     name  = "nycitibike-data-transform"
#     # name = element(split(element(split(var.github_repo_path, "/"), 4), "."), 0)
#     # repo_name   = google_cloudbuildv2_repository.gh_transform_repo.id
#     push { branch = "^main$" }
#   }
# }




# resource "google_cloudbuild_trigger" "cloud_bld_trigger3" {
#   name        = "cloud-bld-trigger3"
#   description = "Trigger with repository_event_config and filename"
#   provider    = google-beta
#   location    = var.region
#   filename    = "Dockerfile"
#   repository_event_config {
#     repository = google_cloudbuildv2_repository.gh_transform_repo.id
#     push {
#       branch = "^main$"
#     }
#   }
# }

resource "google_cloudbuild_trigger" "cloud_bld_trigger7" {
  name        = "cloud-bld-trigger7"
  description = "Trigger with repository_event_config and build"
  provider    = google-beta
  location    = var.region
  # filename    = "Dockerfile"
  repository_event_config {
    repository = google_cloudbuildv2_repository.gh_transform_repo.id
    push {
      branch = "^main$"
    }
  }
  build {
    images = ["gcr.io/$PROJECT_ID/$REPO_NAME:$COMMIT_SHA"]
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
    step {
      name = "gcr.io/cloud-builders/docker"
      args = ["build", "-t", "gcr.io/sbh-nycitibike-pipeline-main/sbh-nycitibike-transform-cb-repogh-usc1-p01:$COMMIT_SHA", "-f", "Dockerfile", "."]
    }
    # step {
    #   name = "gcr.io/cloud-builders/docker"
    #   args = ["push", "gcr.io/$PROJECT_ID/$REPO_NAME:$COMMIT_SHA"]
    # }
    substitutions = {
      _BRANCH_NAME = "^main$"
    }
  }
}

# ["build", "-t", "gcr.io/$PROJECT_ID/$REPO_NAME:$COMMIT_SHA", "-f", "Dockerfile", "."]
# # resource "google_cloudbuild_trigger" "cloud_bld_trigger9" {
# #   name        = "cloud-bld-trigger9"
# #   description = "Trigger with trigger_template and github"
# #   provider    = google-beta
# #   location    = var.region
# #   filename = 
# #   trigger_template {
# #     repo_name   = google_cloudbuildv2_repository.gh_transform_repo.name
# #     project_id  = data.google_project.project.project_id
# #     branch_name = "main"
# #   }
# # }

# resource "google_cloudbuild_trigger" "cloud_bld_trigger4" {
#   name        = "cloud-bld-trigger4"
#   description = "Trigger with trigger_template and github_file_source block"
#   provider    = google-beta
#   location    = var.region
#   trigger_template {
#     repo_name   = google_cloudbuildv2_repository.gh_transform_repo.name
#     project_id  = data.google_project.project.project_id
#     branch_name = "main"
#   }
#   git_file_source {
#     # name      = "nycitibike-data-transform"
#     path      = "Dockerfile"
#     repo_type = "GITHUB"
#     # repository =  If unspecified, the repo from which the trigger invocation originated is assumed to be the repo from which to read the specified path
#     # name = element(split(element(split(var.github_repo_path, "/"), 4), "."), 0)
#     # repo_name   = google_cloudbuildv2_repository.gh_transform_repo.id
#   }
#   # repository_event_config {
#   #   repository = google_cloudbuildv2_repository.gh_transform_repo.id
#   #   push {
#   #     branch = "^main$"
#   #   }
#   # }
# }
# resource "google_cloudbuild_trigger" "cloud_bld_trigger" {
#   name        = "cloud-bld-trigger"
#   description = "Trigger with github and build blocks"
#   provider    = google-beta
#   location    = var.region
#   github {
#     owner = "juicero-chief-juice-officer"
#     name  = "nycitibike-data-transform"
#     # name = element(split(element(split(var.github_repo_path, "/"), 4), "."), 0)
#     # repo_name   = google_cloudbuildv2_repository.gh_transform_repo.id
#     push { branch = "^main$" }
#   }
#   build {
#     # cd dbt/nycitibike-transform/ && 
# docker build \
#     -t gcr.io/sbh-nycitibike-pipeline-main/github.com/juicero-chief-juice-officer/nycitibike-data-transform:$COMMIT_SHA \
#     -f Dockerfile \
#     .
#     images = ["gcr.io/$PROJECT_ID/$REPO_NAME:$COMMIT_SHA"]
#     options {
#       logging = "CLOUD_LOGGING_ONLY"
#     }
#     step {
#       name = "gcr.io/cloud-builders/docker"
#       args = ["build", "-t", "gcr.io/$PROJECT_ID/$REPO_NAME:$COMMIT_SHA", "-f", "Dockerfile", "."]
#     }
#     substitutions = {
#       _BRANCH_NAME = "^main$"
#     }
#   }
#   depends_on = [null_resource.stall_30_seconds]
# }
# trigger_template {
#   # repo_name  = google_cloudbuildv2_repository.gh_transform_repo.name
#   repo_name = var.cloud_build_repo_name
#   # repo_name  = var.cloud_build_repo_name
#   project_id = data.google_project.project.project_id
#   # dir  = "dbt/nycitibike_transform"
#   branch_name = "main"
# }
# service_account = "projects/${data.google_project.project.project_id}/serviceAccounts/${data.terraform_remote_state.config1.outputs.clrn_service_account}"
# filename    = "dbt/nycitibike_transform/Dockerfile"
# trigger_template {
#   # repo_name  = google_cloudbuildv2_repository.gh_transform_repo.name
#   repo_name = var.github_repo_path
#   # repo_name  = var.cloud_build_repo_name
#   project_id = data.google_project.project.project_id
#   # dir  = "dbt/nycitibike_transform"
#   branch_name = "main"
# }
# # step {
# #   name = "gcr.io/cloud-builders/docker"
# #   # name = "gcr.io/cloud-builders/docker"
# #   # entrypoint = "bash"
# #   args = ["gcloud", "auth", "configure-docker", "gcr.io"]
# # }
# step {
#   name = "gcr.io/cloud-builders/docker"
#   # dir  = "dbt/nycitibike_transform" // or specify the directory where Dockerfile is located if it's not in the root
#   args = ["build", "-t", "dbt-latest:v0", "."]
#   # args = ["build", "-t", "gcr.io/${data.google_project.project.project_id}/dbt-latest:v0", "."]
#   # args = ["build -t gcr.io/${data.google_project.project.project_id}/dbt-latest:v0 ."]
# }
# # step {
# #   name = "gcr.io/cloud-builders/docker"
# #   args = ["sleep", "50"]
# # }
# step {
#   name = "gcr.io/cloud-builders/docker"
#   args = ["docker", "tag", "dbt-latest:v0", "gcr.io/${data.google_project.project.project_id}/${google_cloudbuildv2_repository.gh_transform_repo.name}/dbt-latest:v0"]
# }
# step {
#   name = "gcr.io/cloud-builders/docker"
#   # dir  = "dbt/nycitibike_transform" // or specify the directory where Dockerfile is located if it's not in the root
#   args = ["push", "gcr.io/${data.google_project.project.project_id}/${google_cloudbuildv2_repository.gh_transform_repo.name}/dbt-latest:v0"]
# }
# }

# }
# git_file_source {
#   path      = "dbt/nycitibike_transform"
#   repo_type = "GITHUB" #"CLOUD_SOURCE_REPOSITORIES"
# }


# ##################
# ## Cloud Run
# ##################

### create a cloud run service that pulls the dbt-bigquery image and runs it using permissions contained in the cloud run service account/secret
# resource "google_cloud_run_service" "dbt_clrn_service" {

# │ Error: Error waiting to create Service: Error waiting for Creating Service: Error code 13, message: 
#     Revision 'sbh-nycitibike-transform-cr-dbtservice-usc1-p01-00001-285' is not ready and cannot serve traffic. 
#         Image 'gcr.io/sbh-nycitibike-pipeline-main/dbt-latest:v0' not found.
resource "google_cloud_run_v2_service" "dbt_clrn_service" {
  provider = google-beta
  name     = var.cloud_run_service_name
  location = var.region
  template {
    service_account = data.terraform_remote_state.config1.outputs.clrn_service_account
    containers {
      # image = google_artifact_registry_repository.cb_ar_repo.name
      # image = "gcr.io/${data.google_project.project.project_id}/${google_cloudbuildv2_repository.gh_transform_repo.name}:latest"
      # image = "gcr.io/$PROJECT_ID/$REPO_NAME:$COMMIT_SHA"
      image = "gcr.io/${data.google_project.project.project_id}/${google_cloudbuildv2_repository.gh_transform_repo.name}"
    }
  }
  depends_on = [google_cloudbuild_trigger.cloud_bld_trigger7]
  # depends_on = [google_cloudbuild_trigger.example_trigger]
  # traffic { #100%/latest_revision=true are defaults)
  #   percent = 100
  #   # latest_revision = true
  # }
}

# ##################
# ## Cloud Scheduler
# ##################
# ### Create a scheduled job that will run dbt every 4 hours. 
# resource "google_cloud_scheduler_job" "job" {
#   name             = "cld_sched_invoke_build_run"
#   description      = "Job to involke Cloud Run dbt every 4 hours a day"
#   schedule         = "* */4 * * *"
#   time_zone        = "America/New_York"
#   attempt_deadline = "320s"
#   provider         = google-beta

#   retry_config {
#     retry_count = 1
#   }

#   http_target {
#     http_method = "GET"
#     # uri         = google_cloud_run_v2_service.dbt_clrn_service.status[0].url
#     uri = google_cloud_run_v2_service.dbt_clrn_service.uri
#     oidc_token {
#       service_account_email = data.google_compute_default_service_account.default.email
#     }
#   }
# }


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

# resource "google_bigquery_dataset" "nested_datasets" {
#   for_each   = var.external_tables_to_create
#   dataset_id = each.value.dataset
#   location   = var.region
# }

# resource "google_bigquery_dataset" "nested_datasets_dev" {
#   for_each   = var.external_tables_to_create
#   dataset_id = "DEV-${each.value.dataset}"
#   location   = var.region
# }

# resource "google_bigquery_table" "external_tables" {
#   for_each   = var.external_tables_to_create
#   dataset_id = each.value.dataset
#   table_id   = each.value.table_name
#   external_data_configuration {
#     autodetect    = true
#     source_format = "PARQUET"
#     compression   = "GZIP"
#     source_uris   = ["gs://${var.gcs_bucket_name}/${each.value.gcs_path}*.parquet"]
#   }
#   # time_partitioning { #you cannot partition an external table
#   #   type  = "DAY"
#   #   field = each.value.partition_field
#   # }
#   depends_on = [google_bigquery_dataset.nested_datasets]
# }

# resource "google_bigquery_table" "external_tables-dev" {
#   for_each = var.external_tables_to_create

#   dataset_id = "DEV_${each.value.dataset}"
#   table_id   = each.value.table_name
#   external_data_configuration {
#     autodetect    = true
#     source_format = "PARQUET"
#     compression   = "GZIP"
#     source_uris   = ["gs://${var.gcs_bucket_name}/${each.value.gcs_path}*.parquet"]
#   }
#   # time_partitioning { #you cannot partition an external table
#   #   type  = "DAY"
#   #   field = each.value.partition_field
#   # }
#   depends_on = [google_bigquery_dataset.nested_datasets_dev]
# }





# # # resource "google_compute_resource_policy" "gce_schedule" {
# # #   name   = var.gce_policy_name
# # #   region = var.region
# # #   description = var.gce_policy_desc
# # #   instance_schedule_policy {
# # #     vm_start_schedule {
# # #       schedule = var.gce_policy_sched_start
# # #     }
# # #     vm_stop_schedule {
# # #       schedule = var.gce_policy_sched_stop
# # #     }
# # #     time_zone = var.gce_policy_timezone
# # #   }
# # # }

# # # resource "google_compute_instance" "default" {
# # #   name         = var.gce_inst_name
# # #   machine_type = var.gce_machine_type
# # #   zone         = var.gce_zone
# # #   # resource_policies = [google_compute_resource_policy.gce_schedule.id]
# # #   network_interface {
# # #     network = "default"
# # #     access_config {
# # #       network_tier = "STANDARD"
# # #     }
# # #   }
# # #   boot_disk {
# # #     initialize_params {
# # #       image = var.gce_image
# # #       size = var.gce_image_size
# # #     }
# # #   }

# # # Not Functional; Do not Use
# # # metadata_startup_script = <<SCRIPT
# # # touch install_pt1.sh install_pt2.sh
# # # echo "#!/bin/bash
# # # # Go to home directory
# # # cd ~
# # # # You can change what anaconda version you want on the anaconda site
# # # #!/bin/bash
# # # wget https://repo.anaconda.com/archive/Anaconda3-2023.03-1-Linux-x86_64.sh
# # # bash Anaconda3-2023.03-1-Linux-x86_64.sh -b -p ~/anaconda3
# # # rm Anaconda3-2023.03-1-Linux-x86_64.sh
# # # echo 'export PATH="~/anaconda3/bin:$PATH"' >> ~/.bashrc 
# # # # messy workaround for difficulty running source ~/.bashrc from shell script in ubuntu
# # # # sourced from askubuntu question 64387
# # # eval '$(cat ~/.bashrc | tail -n +10)'
# # # conda init
# # # conda update conda
# # # conda --version" > install_pt1.sh
# # # echo "#!/bin/bash
# # # sudo apt-get update -y
# # # sudo apt-get upgrade -y
# # # pip install prefect prefect-gcp
# # # prefect cloud login -k <INSERT_API_KEY>
# # # echo 'prefect agent start -q default' >> ~/.bashrc" > install_pt2.sh
# # # sudo chmod +x install_pt1.sh install_pt2.sh
# # # ./install_pt1.sh
# # # source ~/.bashrc
# # # ./install_pt2.sh
# # # source ~/.bashrc
# # # SCRIPT

# # # service_account {
# # #   # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
# # #   email  = google_service_account.gce_default.email
# # #   scopes = ["cloud-platform","https://www.googleapis.com/auth/compute"]
# # # }

# # # This is deactivated for now. 
# # # Instead we can use gcloud compute instances add-resource-policies


# # # # Deactivated pending fix.
# # # # Give compute instance start/stop permissions to default GCE SA
# # # resource "google_service_account_iam_member" "gce_default_start_stop" {
# # #   role               = "roles/compute.Admin"
# # #   service_account_id = data.google_compute_default_service_account.default.name
# # #   member             = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
# # # }

# # # scheduling {
# # #   preemptible = var.gce_preemptible
# # #   automatic_restart = var.gce_auto_restart
# # # }


# # # }



# # # --Created in previous project--
# # # Data Lake Bucket
# # # no updates needed here; though we removed the _${var.project} as we were confident we wouldn't risk duplicate naming when creating
# # # resource "google_storage_bucket" "data-lake-bucket" {
# # #   name          = "${var.gcs_bucket_name}"#_${var.project}" # Uses Local variable. Concatenates DL bucket & Project name for unique naming
# # #   location      = var.region

# # #   # Optional, but recommended settings:
# # #   storage_class = var.storage_class
# # #   uniform_bucket_level_access = true

# # #   versioning {  
# # #     enabled     = true
# # #   }

# # #   lifecycle_rule {
# # #     action {
# # #       type = "Delete"
# # #     }
# # #     condition {
# # #       age = 30  // days
# # #     }
# # #   }

# # #   force_destroy = true
# # # }

# # # --Created in previous project--
# # # Data Warehouse
# # # Ref: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_dataset
# # # resource "google_bigquery_dataset" "dataset" {
# # #   dataset_id = var.bq_dataset
# # #   project    = var.project
# # #   location   = var.region
# # # }




## Create a trigger thatruns cloudbuild anytime an update is made to the gcp cloud build repo, which itself is updated based on changes to the main github brand
# resource "google_cloudbuildv2_repository" "example_repo" {
#   name              = var.cloud_build_repo_name
#   project           = data.google_project.project.project_id
#   location          = var.region
#   parent_connection = google_cloudbuildv2_connection.clbd_gh_connection.name
#   provider          = google-beta
#   remote_uri        = var.github_repo_path
#   depends_on        = [null_resource.check_cloudbuild_state]
#   # ... other repository configuration ...
# }

# resource "google_cloudbuild_trigger" "example_trigger" {
#   name        = "example-trigger"
#   description = "Example trigger"

#   trigger_template {
#     dir = "dbt/nycitibike_transform"
#     # filename = "Dockerfile"
#   }

#   github {
#     owner = "juicero-chief-juice-officer"
#     name  = "nycitibike-data-transform"
#     # tag_pattern = "v1.*"
#   }
#   build {
#     step {
#       name = "gcr.io/cloud-builders/docker"
#       dir  = "dbt/nycitibike_transform" // or specify the directory where Dockerfile is located if it's not in the root
#       args = ["build", "-t", "gcr.io/${data.google_project.project.project_id}/dbt-latest:v0", "."]
#     }
#     step {
#       name = "gcr.io/cloud-builders/docker"
#       args = ["sleep", "50"]
#     }
#     step {
#       name = "gcr.io/cloud-builders/docker"
#       args = ["push", "gcr.io/${data.google_project.project.project_id}/dbt-latest:v0"]
#     }
#     substitutions = {
#       _REPO_NAME = google_cloudbuildv2_repository.example_repo.name
#       # ... other substitutions ...
#     }

#     # ... other trigger configuration ...
#   }
# }
