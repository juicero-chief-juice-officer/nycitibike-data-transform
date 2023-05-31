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


### Instantiate the secret for the cloud run service account to reference
resource "google_secret_manager_secret" "clrn_secret" {
  # account_id         = var.sa_for_dbt_clrun
  # secret_id        = google_service_account.sa[var.sa_for_dbt_clrun-key].id #.email #.service_account.email
  secret_id = "${var.sa_for_dbt_clrun}-key-clrn-secret-file"
  replication {
    automatic = true
  }
}

## Keys from service accounts
### only created if create_key flag is true, and if it's NOT the github or cloudrun sa
# resource "google_service_account_key" "mykeys" {
#   for_each = { for key, value in var.svc_accts_and_roles : key => value if value["create_key"] && key != var.sa_for_dbt_clrun }
#   # service_account_id = "${google_service_account.sa[each.key]}"
#   service_account_id = "projects/${var.project}/serviceAccounts/${each.key}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
#   depends_on         = [google_project_iam_member.sa-accounts-iam]
# }

# ### Specific Key for the cloudrun service account
# resource "google_service_account_key" "key_clrn" {
#   # service_account_id = "${google_service_account.sa[each.key]}"
#   service_account_id = "projects/${var.project}/serviceAccounts/${var.sa_for_dbt_clrun}-${random_id.suffix.hex}@${var.project}.iam.gserviceaccount.com"
#   depends_on         = [google_project_iam_member.sa-accounts-iam]
#   key_algorithm      = "KEY_ALG_RSA_2048"
#   private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
# }

# output "clrn_service_account_key" {
#   value     = google_service_account_key.key_clrn.private_key
#   sensitive = true
# }
# output "clrn_service_account_key_attributes" {
#   value     = google_service_account_key.key_clrn
#   sensitive = true
# }

output "clrn_service_account" {
  value     = google_service_account.sa[var.sa_for_dbt_clrun].name
  sensitive = false
}

output "random_id_suffix" {
  value       = random_id.suffix
  byte_length = 2
}
