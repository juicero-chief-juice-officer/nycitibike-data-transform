variable "project" {
  description = "full, unique id of GCP project"
  type        = string
}

variable "svc_accts_and_roles" {
  description = "Names of service accounts and roles they should be given."
  type        = any
}

locals {
  ts = timestamp()

  svc_accts_iam_flat = merge([
    for svc_acct, svc_acct_attrs in var.svc_accts_and_roles : {
      for role in svc_acct_attrs.roles :
      "${svc_acct}-${role}" => {
        svc_acct_to_apply_role_to = "${svc_acct}"
        role_to_apply             = "${role}"
      }
    }
  ]...)
}

variable "list_apis_to_enable" {
  type        = set(string)
  description = "Any APIs you want to ensure are enabled."
  default     = []
}
# variable "project_number_out" {

# }

variable "gcs_bucket_name" {
  description = "Bucket name for Data Lake."
  type        = string
  default     = "tmp-unknown-datalake-bucket"
}

variable "external_tables_to_create" {
  description = "Map of external tables to create"
  type = map(object({
    gcs_path        = string
    dataset         = string
    table_name      = string
    partition_field = string
  }))
}

variable "region" {
  default = "us-central1"
  type    = string
  validation {
    condition     = substr(var.region, 0, 2) == "us"
    error_message = "Error: The location must be within 'us'."
  }
}

variable "github_token_path" {
  validation {
    condition     = length(regexall("^.*\\.txt$", var.github_token_path)) > 0
    error_message = "File name must end with .txt"
  }
}

variable "sa_for_github" {
  type        = string
  description = "Service account for GitHub"
  # A future version might validate whether this SA is in the list of SAs created
}


variable "sa_for_dbt_clrun" {
  type        = string
  description = "Service account for Cloud Run"
  # A future version might validate whether this SA is in the list of SAs created
}

variable "cloud_build_repo_name" {
}

variable "cloud_run_service_name" {
  type        = string
  description = "Name of the cloud run service to create."
}

variable "cloud_run_container_path" {
  type        = string
  description = "Path to docker container."
}

variable "github_repo_path" {
  type = string
  validation {
    condition     = length(regexall("^.*\\.git$", var.github_repo_path)) > 0
    error_message = "File name must end with .git"
  }
}

# variable "storage_class" {
#   description = "Storage class type for your bucket. Check official docs for more info."
#   default     = "STANDARD"
# }

# variable "bq_dataset" {
#   description = "BigQuery Dataset that raw data (from GCS) will be written to"
#   type        = string
#   default     = "gbqdwh_source_data"
# }


##
#Artifact registry
##
variable "registry_repo_name" {
  description = "Docker registry"
  type        = string
}

variable "repo_description" {
  description = "Docker registry for prefect "
  type        = string
}

variable "repo_format" {
  description = "Format, usually 'DOCKER'"
  type        = string
  default     = "DOCKER"
}

##
# Compute Engine Resource/Schedule
# Comment out here, in main.tf, and in terraform.tfvars if not using
##

# variable gce_policy_name {
#   description = "Name of Schedule resource policy."
#   type        = string
# }

# variable gce_policy_desc {
#   description = "Name of Schedule resource policy."
#   type        = string
#   default     = "Sets a schedule to run for 1-1:15 daily at 3am NYC time."
# }

# variable gce_policy_sched_start {
#   description = "Cron schedule for starting time"
#   type        = string
#   #default once a day 
#   default     = "45 2 * * *"
# }

# variable gce_policy_sched_stop {
#   description = "Cron schedule for stop time"
#   type        = string
#   #default once a day
#   default     = "0 4 * * *"
# }

# variable gce_policy_timezone {
#   description = "Timezone in which to run schedule."
#   type        = string
#   default     = "America/New_York"
# }


# ##
# # Compute Engine
# ##
# variable "gce_image" {
#   description = "Image, eg the OS, from google image registry to use"
#   type        = string
# default       = "ubuntu-2004-focal-v20230302"
# }

# variable gce_inst_name {
#   description = ""
#   type        = string
# }

# variable gce_zone {
#   description = "Specific Zone (us-central1-a) to run instance in."
#   type        = string
#   default     = "us-central1-a"
# }

# variable gce_image_size {
#   description = "Number of GB for image"
#   type        = number
#   default     =  20
# }

# variable gce_machine_type {
#   description = "Machine type for GCE"
#   type        = string
#   default     =  "e2-micro"
# }

# variable gce_preemptible {
#   description = "Whether the VM can be stopped by GCE to allocate capacity to other VMs. They are cheaper. These are being phased out for 'Spot' VMs, which have  more features."
#   type        = bool
#   default     = false
# }

# variable gce_auto_restart {
#   description = ""
#   type        = bool
#   default     = true
# }
