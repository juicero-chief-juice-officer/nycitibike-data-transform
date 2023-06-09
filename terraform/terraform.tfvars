#GCP settings
project = "sbh-nycitibike-pipeline-main"
region  = "us-central1"

## NOTE!
# This is not used, and only remains for reference. 
# list_apis_to_enable = ["secretmanager.googleapis.com"
#   , "cloudbuild.googleapis.com"
#   , "cloudscheduler.googleapis.com"
# ]

# Service Accounts and Roles
# map/dict with key service-account name and values map/dict of description and list of roles to be assigned
# EG :     = {"generic-primary-svc-acct" = {
#                         description = "Generic Primary SA with limited view access"
#                         roles=        ["roles/browser"]
#                           }
#          ... }


svc_accts_and_roles = {
  "dbt-trnsfrm-sa2" = {
    description   = "SA to be used by DBT to transform data and update/manage bigquery data warehouse."
    create_key    = true
    secret_access = true
    roles = [
      "roles/storage.admin"
      , "roles/iam.serviceAccountUser"
      , "roles/bigquery.admin"
      , "roles/run.admin"
    ]
  }
  "dbt-schedinvoke-sa1" = {
    description   = "SA to be used by Cloud Scheduler to invoke Cloud Run."
    create_key    = false
    secret_access = false
    roles = [
      "roles/run.invoker"
      # , "roles/storage.admin"
      , "roles/iam.serviceAccountUser"
      , "roles/run.serviceAgent"
      # , "roles/run.admin"
    ]
  }

}
# SQL naming convention
# Triple underscore (`___`) is used exclusively to separate the dataset type from the dataset name.
#   This lets us, essentially, nest a second layer in between project_name and table_name
#   We use triple because it is so obvious (and inconvenient) as to be memorable
# Lowercase letters are only used to separate dataset sub-types, specifically `2x_DIM`

datasets_to_create = [
  "1_SRC___NYCITIBIKE"
  , "1_SRC___AUX_TLC"
  , "2_STG___NYCITIBIKE"
  , "2_STG___AUX_TLC"
  , "2_DIM___AUX_TLC"
  , "3_PREP"
  , "4_MART"
]

external_tables_to_create = {
  "raw_citibike_rides" = {
    gcs_path   = "data/"
    dataset    = "1_SRC___NYCITIBIKE"
    table_name = "TRIPS"
    # filename_regex  = ""
  }
  "aux_raw_fhv_green" = {
    gcs_path   = "aux_data/tlc_trips/green/"
    dataset    = "1_SRC___AUX_TLC"
    table_name = "RIDES_GREEN"
  }
  "aux_raw_fhv_yellow" = {
    gcs_path   = "aux_data/tlc_trips/yellow/"
    dataset    = "1_SRC___AUX_TLC"
    table_name = "RIDES_YELLOW"
  }
  "aux_raw_fhv_fhv" = {
    gcs_path   = "aux_data/tlc_trips/fhv/"
    dataset    = "1_SRC___AUX_TLC"
    table_name = "RIDES_FHV"
  }
}

sa_for_github = "dbt-trnsfrm-sa2"

#must be a service account name in svc_accts_and_roles 
sa_for_dbt_clrun         = "dbt-trnsfrm-sa2"
cloud_run_service_name   = "sbh-nycitibike-transform-cr-dbtservice-usc1-p01"
cloud_run_container_path = ""

github_token_path     = "../../secrets/alt_pat.txt"
cloud_build_repo_name = "sbh-nycitibike-transform-cb-repogh-usc1-p01"
github_repo_path      = "https://github.com/juicero-chief-juice-officer/nycitibike-data-transform.git"

#Artifact registry
registry_repo_name = "xxxxxxxxsbh-nycitibike-transform-ar-vmrepo-usc1-p01xxxxxx"
repo_description   = "For docker image which will run dbt"
repo_format        = "DOCKER"


# --Created in previous project; used here for reference--
#Data Lake Cloud Storage Bucket
gcs_bucket_name = "sbh-nycitibike-pipeline-gcsdlb-rides-p01"
# # gcs_storage_class = "STANDARD"

# --Created in previous project--
#Data Warehouse BigQuery
bq_dataset = "gbqdwh_rides"
