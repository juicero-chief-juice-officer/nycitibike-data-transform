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
      sleep 60
EOF
  }
}


resource "null_resource" "check_cloudbuild_state" {
  triggers = {
    connection_id = google_cloudbuildv2_connection.clbd_gh_connection.id
  }
  provisioner "local-exec" {
    # the [[]] is needed to ask for a new test each time, rather than using the same test again and again
    command = <<-EOF
      until [[ $(gcloud alpha builds connections describe ${self.triggers.connection_id} --format="get(installationState.stage)") == "COMPLETE" ]]; do
        echo "waiting for installation to complete..."
        sleep 5
      done
EOF
  }
}


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
  ### You can elither delete at console.cloud.google.com/cloud-build/repositories/2nd-gen  or comment out this resource and rerun. 
  provider = google-beta
  location = var.region
  name     = "clbd_gh_connection"
  github_config {
    app_installation_id = 37951852
    authorizer_credential {
      oauth_token_secret_version = data.terraform_remote_state.config1.outputs.github_secret_id
    }
  }
}

## Create a gcp repo for the github repo to be pulled into
resource "google_cloudbuildv2_repository" "gh_transform_repo" {
  provider          = google-beta
  location          = var.region
  name              = var.cloud_build_repo_name
  parent_connection = google_cloudbuildv2_connection.clbd_gh_connection.name
  remote_uri        = var.github_repo_path
  depends_on = [
    null_resource.check_cloudbuild_state,
  google_cloudbuildv2_connection.clbd_gh_connection] #despite appearances, this does not work as it doesn't check for *state* of connection
}

resource "google_cloudbuild_trigger" "cloud_bld_trigger" {
  name        = "cloud-bld-trigger-gh"
  description = "Trigger with repository_event_config and build"
  provider    = google-beta
  location    = var.region
  repository_event_config { # What triggers the trigger
    repository = google_cloudbuildv2_repository.gh_transform_repo.id
    push {
      branch = "^main$"
    }
  }
  build {                                         #What to do when triggered
    images = ["gcr.io/$PROJECT_ID/$REPO_NAME:v0"] # gcr.io/$PROJECT_ID/$REPO_NAME:$COMMIT_SHA"]
    step {
      name = "gcr.io/cloud-builders/docker"
      dir  = "dbt/nycitibike_transform"
      args = ["build", "-t", "gcr.io/$PROJECT_ID/${var.cloud_build_repo_name}:v0", "-f", "Dockerfile", "."]
    }
    step {
      name       = "gcr.io/cloud-builders/gcloud"
      entrypoint = "/bin/bash"
      dir        = "dbt/nycitibike_transform"
      args       = ["-c", "docker push gcr.io/$PROJECT_ID/${var.cloud_build_repo_name}:v0"]
      # Note that pushing the way below way will lead to an error in the trigger set up
      # args = ["push", "gcr.io/$PROJECT_ID/${var.cloud_build_repo_name}:v0"] 
    }
    substitutions = {
      _BRANCH_NAME = "^main$"
    }
  }
}

#################
# Cloud Run
#################

resource "google_cloud_run_v2_service" "dbt_clrn_service" {
  provider = google-beta
  name     = var.cloud_run_service_name
  location = var.region
  template {
    service_account = data.terraform_remote_state.config1.outputs.clrn_service_account
    containers {
      image = "gcr.io/${data.google_project.project.project_id}/${var.cloud_build_repo_name}:v0"
    }
  }
  depends_on = [google_cloudbuild_trigger.cloud_bld_trigger, null_resource.stall_30_seconds]
  # traffic { # 100%/latest_revision=true are defaults)
  #   percent = 100
  #   # latest_revision = true
  # }
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
  provider         = google-beta

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "GET"
    uri         = google_cloud_run_v2_service.dbt_clrn_service.uri
    # uri         = google_cloud_run_v2_service.dbt_clrn_service.status[0].uri
    oidc_token {
      service_account_email = data.google_compute_default_service_account.default.email
    }
  }
}


#################
# Data Warehouse
#################

# Create Dev BigQuery Instance
# resource "google_bigquery_dataset" "dataset" {
#   project                    = var.project
#   dataset_id                 = upper(replace(var.bq_dataset, "-", "_"))
#   location                   = var.region
#   delete_contents_on_destroy = true
# }


# resource "google_bigquery_dataset" "datasets-dev" {
#   project                    = var.project
#   dataset_id                 = "DEV_${upper(replace(var.bq_dataset, "-", "_"))}"
#   location                   = var.region
#   delete_contents_on_destroy = true
# }

resource "google_bigquery_dataset" "nested_datasets" {
  for_each = toset(var.datasets_to_create)

  dataset_id = "CORE_${upper(replace(each.value, "-", "_"))}"
  project    = var.project
  location   = var.region
  # delete_contents_on_destroy = true
}

resource "google_bigquery_dataset" "nested_datasets_dev" {
  for_each = toset(var.datasets_to_create)

  project    = var.project
  dataset_id = "DEV_${upper(replace(each.value, "-", "_"))}"
  location   = var.region
  # delete_contents_on_destroy = true
}

# Create external Tables for BigQuery to pull from
## This cannot be done in dbt, so we do it with terraform

# resource "google_bigquery_table" "external_tables" {
#   for_each = var.external_tables_to_create

#   dataset_id = upper(replace(var.bq_dataset, "-", "_"))
#   table_id   = upper(replace("${each.value.dataset}_${each.value.table_name}", "-", "_"))
#   # deletion_protection = true
#   external_data_configuration {
#     autodetect    = true
#     source_format = "PARQUET"
#     compression   = "GZIP"
#     source_uris   = ["gs://${var.gcs_bucket_name}/${each.value.gcs_path}*.parquet"]
#   }
# }

# resource "google_bigquery_table" "external_tables-dev" {
#   for_each = var.external_tables_to_create

#   dataset_id = "DEV_${upper(replace(var.bq_dataset, "-", "_"))}"
#   table_id   = upper(replace("${each.value.dataset}_${each.value.table_name}", "-", "_"))
#   # deletion_protection = true
#   external_data_configuration {
#     autodetect    = true
#     source_format = "PARQUET"
#     compression   = "GZIP"
#     source_uris   = ["gs://${var.gcs_bucket_name}/${each.value.gcs_path}*.parquet"]
#   }
# }

### NESTED
resource "google_bigquery_table" "external_tables_nested" {
  for_each = var.external_tables_to_create

  dataset_id          = "CORE_${upper(replace(each.value.dataset, "-", "_"))}"
  table_id            = upper(replace(each.value.table_name, "-", "_"))
  deletion_protection = false
  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    compression   = "GZIP"
    source_uris   = ["gs://${var.gcs_bucket_name}/${each.value.gcs_path}*.parquet"]
  }
  # time_partitioning { #you cannot partition an external table
  #   type  = "DAY"
  #   field = each.value.partition_field
  # }
  depends_on = [google_bigquery_dataset.nested_datasets]
}

resource "google_bigquery_table" "external_tables_nested-dev" {
  for_each = var.external_tables_to_create

  dataset_id          = "DEV_${upper(replace(each.value.dataset, "-", "_"))}"
  table_id            = upper(replace(each.value.table_name, "-", "_"))
  deletion_protection = false
  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    compression   = "GZIP"
    source_uris   = ["gs://${var.gcs_bucket_name}/${each.value.gcs_path}*.parquet"]
  }
  # time_partitioning { #you cannot partition an external table
  #   type  = "DAY"
  #   field = each.value.partition_field
  # }
  depends_on = [google_bigquery_dataset.nested_datasets_dev]
}
