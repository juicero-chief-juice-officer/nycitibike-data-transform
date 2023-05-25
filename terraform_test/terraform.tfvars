#RENAME THIS AS `terraform.tfvars`
#GCP settings
project = "sbh-nycitibike-pipeline-main"
region  = "us-central1"

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
      , "roles/iam.serviceAccountUser"
      , "roles/run.serviceAgent"
    ]
  }

}

external_tables_to_create = {
  "raw_citibike_rides" = {
    gcs_path        = "data/"
    dataset         = "1_SRC_NYCITIBIKE"
    table_name      = "TRIPS"
    partition_field = "started_at"
  }
  "aux_raw_fhv_green" = {
    gcs_path        = "aux_data/for_hire_vehicle_trips/green/"
    dataset         = "1_SRC_AUX_TLC_GREEN_RIDES"
    table_name      = "RIDES"
    partition_field = "lpep_pickup_datetime"
  }
  "aux_raw_fhv_yellow" = {
    gcs_path        = "aux_data/for_hire_vehicle_trips/yellow/"
    dataset         = "1_SRC_AUX_TLC_YELLOW_RIDES"
    table_name      = "RIDES"
    partition_field = "tpep_pickup_datetime"
  }
  "aux_raw_fhv_fhv" = {
    gcs_path        = "aux_data/for_hire_vehicle_trips/fhv/"
    dataset         = "1_SRC_AUX_TLC_FHV_RIDES"
    table_name      = "RIDES"
    partition_field = "Pickup_datetime"
  }
}


sa_for_github = "dbt-trnsfrm-sa2"

#must be a service account name in svc_accts_and_roles 
sa_for_dbt_clrun         = "dbt-trnsfrm-sa2"
cloud_run_service_name   = "sbh-nycitibike-transform-cr-dbtservice-usc1-p01"
cloud_run_container_path = ""

github_token_path     = "secrets/dbt_pat.txt"
cloud_build_repo_name = "sbh-nycitibike-transform-cb-repogh-usc1-p01"
github_repo_path      = "https://github.com/juicero-chief-juice-officer/nycitibike-data-transform.git"

#Artifact registry
registry_repo_name = "sbh-nycitibike-transform-ar-vmrepo-usc1-p01"
repo_description   = "For docker image which will run dbt"
repo_format        = "DOCKER"


# --Created in previous project--
# #Data Lake Cloud Storage Bucket
# gcs_bucket_name = "sbh-nycitibike-pipeline-gcsdlb-rides-p01"
# # gcs_storage_class = "STANDARD"

# --Created in previous project--
# #Data Warehouse BigQuery
# bq_dataset = "gbqdwh_rides"
