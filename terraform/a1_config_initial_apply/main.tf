terraform {
  required_version = ">= 1.0"
  backend "gcs" {
    bucket = "z_infra_resources01"
  } # Can change from "local" to "gcs" (for google) or "s3" (for aws), if you would like to preserve your tf-state online
  # terraform will not create the bucket, so bucket must be created from CLI/GUI
  required_providers {
    google-beta = ">=3.8"
    google = {
      version = "~> 4.0.0"
    }
  }
}
##################################################################################
##################################################################################
# PROVIDERS
##################################################################################
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
##################################################################################
# DATA/OUTPUTS
##################################################################################
##################################################################################

## Information we'll reference over the course of this infrastructure build
data "google_project" "project" {
  project_id = var.project
}

data "google_compute_default_service_account" "default" {
}

##################################################################################
##################################################################################
# RESOURCES
##################################################################################
##################################################################################

## Random Suffix 
### Generate random brief suffix to ensure service-account names are globally unique.
resource "random_id" "suffix" {
  byte_length = 2
}

##################################################################################
# Note: As discussed in readme, the project service api enabling module appears very inconsistent (there are a number of other reports of this)
# Below are 3 different attempts at doing so in terraform.
# Ensure that these are complimented, as appropriate, by depends_on arguments in the relevant resources
##################################################################################
## [Enabling APIs 1 of 3]
## Leaving this in, but commented out.
## This is one considered approach to navigating the inconsistency around enabling APIs. 
## It is paired with the folder a0_apis_enable

# module "enable_apis" {
#   source = "./a0_apis_enable"

#   project        = var.project
#   apis_to_enable = var.list_apis_to_enable
# }

## [Enabling APIs 2 of 3]
## Leaving this in, but commented out
## Enable multiple services with a for_each.
### note that tf previously had both google_project_service and google_project_service*s*; but services is deprecated
# resource "google_project_service" "svcs" {
#   for_each           = toset(var.list_apis_to_enable)
#   project            = var.project
#   service            = each.value
#   disable_on_destroy = false
# }

## [Enabling APIs 3 of 3]
## Leaving this in, but commented out
## This attempts to use the command line to enable APIs. 
# resource "null_resource" "activate_api_then_sleep_30_seconds" {
#   for_each = toset(var.list_apis_to_enable)
#   provisioner "local-exec" {
#     command = <<-EOF
#       gcloud services enable ${each.key}
#       echo -n "enable ${each.key}; start sleep"
#       sleep 300
# EOF
#   }
# }

## [Enabling APIs Appendix]
## Leaving this in, but commented out
## This attempts to tell terraform to wait upon enabling APIs with project_service
# resource "time_sleep" "wait_60_seconds" {
#   for_each = toset(var.list_apis_to_enable)
#   triggers   = { abc = tostring(google_project_service.svcs[each.key].id) }
#   depends_on = [google_project_service.svcs]
#   create_duration = "60s"
# }
##################################################################################



####################################
## Service Account (If not done via command line.)
####################################

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

####################################
## Secret Manager (If not done via command line or GUI.)
####################################

# GitHub secret

### Instantiate the secret for our github token (not strictly necessary as it's a public repo)
resource "google_secret_manager_secret" "github-token-secret" {
  provider  = google-beta
  secret_id = "github-token-secret"
  replication {
    automatic = true
  }
  # depends_on = [time_sleep.wait_60_seconds, null_resource.activate_api_then_sleep_30_seconds, google_project_service.svcs]
}

### Assign value (version) to the secret with secret data
### Also, again, could be done from GUI so as not to have to store locally. 
resource "google_secret_manager_secret_version" "github_token_secret_version" {
  provider    = google-beta
  secret      = google_secret_manager_secret.github-token-secret.id
  secret_data = file(var.github_token_path)
  depends_on = [
    # time_sleep.wait_60_seconds,
    # null_resource.activate_api_then_sleep_30_seconds,
    google_secret_manager_secret.github-token-secret
  ]
}

## Specfic to GitHub secret
### Get the policy data/permissions for a secret accessor under this project
data "google_iam_policy" "p4sa-secretAccessor" {
  #dbt-trnsfrm-sa2
  provider = google-beta
  binding {
    role    = "roles/secretmanager.secretAccessor"
    members = ["serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"]
  }
}

### Assign that policy data/permissions to the gituhb secret
resource "google_secret_manager_secret_iam_policy" "policy" {
  provider    = google-beta
  secret_id   = google_secret_manager_secret.github-token-secret.secret_id
  policy_data = data.google_iam_policy.p4sa-secretAccessor.policy_data
}

## CloudRun Secret
### Instantiate the secret for the cloud run service account to reference
### The secret itself (the content) will be added by GUI or command-line as a "version"
resource "google_secret_manager_secret" "clrn_secret" {
  # account_id         = var.sa_for_dbt_clrun
  # secret_id        = google_service_account.sa[var.sa_for_dbt_clrun-key].id #.email #.service_account.email
  secret_id = "${var.sa_for_dbt_clrun}-key-clrn-secret-file"
  replication {
    automatic = true
  }
  # depends_on = [time_sleep.wait_60_seconds, null_resource.activate_api_then_sleep_30_seconds]
}

####################################
## Outputs
####################################

output "clrn_service_account" {
  value     = google_service_account.sa[var.sa_for_dbt_clrun].email
  sensitive = false
}

output "github_secret_id" {
  value     = google_secret_manager_secret_version.github_token_secret_version.id
  sensitive = false
}

output "random_id_suffix" {
  value = random_id.suffix
}
