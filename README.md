[[Work in progress!]]

## Preface:
It is important to acknowldge that for many of us, especially those reviewing a GitHub portfolio project, it is a city 


# Process
## 0. Project/Environment/Repo set-up
### 0.a Naming Convention
For GCP naming conventions, we follow the convention described in the companion/precursor project  (nycitibike_data_pipeline)[https://github.com/juicero-chief-juice-officer/nycitibike_data_pipeline].

For SQL (BigQuery) and dbt naming, we take some liberties for the sake of experimentation. 

#### BigQuery Data Warehouse

Bigquery affords 3 hierarchies levels for organizing and managing your Data Warehouse: a Project, a Dataset, and a table. The Project is defined by the GCP project being used, and so is static.

Rather than lean on table names for the differentiation, here we instead put that work on the datasets that contain the tables, in the hope that using more accessible table names may facilitate navigation. Thus datasets are structured as follows: 
```
{ENV}_{Level Numeral}_{Level ID}___{Dataset descriptor}
```

- For our env's, we use `CORE` and `DEV`. I chose `CORE` because it was the first thing that came to mind when looking for a 3-4 letter PROD equivalent that started with A, B, or C.
- For Level Numeral and Level ID we again experiment with a more specified approach:
  - 1. SRC: Source or raw tables. These are often external tables from the GCS data lake. 
  - 2. DIM: Dimension tables
  - 2. STG: Stage tables that are cleaned up, joined and organized, but not aggregated. 
  - 3. PREP: 
  - 4. MART: The final "retail" tables that contains analysis and user-friendly/user-requested tables. 


### 0.b. GitHub
We use GitHub as usual, but do need to ensure that the Cloud Build app is installed on our project. 

### 0.c. Environment setup

We again use poetry (for packages) and conda (for virtual environments). 

```zsh
conda create --name citibike-transform -c conda-forge python=3.11 pip
conda activate citibike-transform
conda install poetry
curl -sSL https://install.python-poetry.org | python3 -
poetry install --no-root
```

## 1. GCP Set-up
As an overview, let's run through what we are going to ask GCP to do for us: 
- Create one or more semi-siloed "service accounts" that can perform certain tasks on our behalf, but which are as much as possible limited to only those tasks. 
- Using one service account, create a space where sensitive/secret information can be stored. It should be stored securely in the cloud in such a way that it can only be accessed by a select few, and only be changed/updated by a select few. 
- Listen for changes to a specific (possibly private) github repo describing a container image, and any time updates/changes are made to the repo, rebuild, store and deploy the image.
- Run the container periodically according to a given/desired schedule.

### Enabling more services:

For simplicity, we do a few things via the gcloud CLI before leaning into terraform. 
First, enable a few more services, using the command `cloud services enable {service url}`, eg `cloud services enable cloudscheduler.googleapis.com`
- Cloud Build
- Cloud Scheduler
- Secret Manager

Next, we generate a Service Account key locally, as terraform does not make it easy to download a key locally. (An alternative is something like 
`terraform apply --auto-approve | grep service_account_key | awk '{print $3}' > /path/to/keyfile.json`)
```
gcloud iam service-accounts keys create ~/path/to/keyfile.json \
  --iam-account my-iam-account@my-project.iam.gserviceaccount.com
gcloud iam service-accounts keys create ../../secrets/dbt-trnsfrm-sa2-key-clrn-secret-file.json \
  --iam-account dbt-trnsfrm-sa2-6534@sbh-nycitibike-pipeline-main.iam.gserviceaccount.com
```

## 2. Docker
We will be hosting/running our own DBT core, rather than using (and paying for) DBT Cloud. Whereas in the previous project, we handled this using GCP's Google Compute Engine, 

### Set up and test
We first build and test our Docker DBT image locally. 

We have 3 files for our Docker setup: `Dockerfile`, `invoke.go` and `setup_script.sh`

Dockerfile is a fairly out-of-the box version of the dbt-bigquery Dockerfile, including the calling of invoke.go. Invoke.go sets up a Go HTTP server, and then calls setup_script.sh when a request comes in. We need to do this because Cloud Run expects HTTP requests. 

With these in place, we run `docker build --tag local-test .` then `docker run local-test` to ensure the image is set up properly.

Finally, ensure that these files are in the proper directory. In our case, we keep them in the same directory as dbt. 

## 3. Initialize dbt
We'll initialize our dbt to have a basic starting place for development. 
```
cd to dbt folder
dbt init --profiles-dir .  
-> enter gcp project name
-> select bigquery
-> select oath?
```

## 4. Terraform (Infrastructure as Code)
Terraform, including installation, is discussed in greater detail in the companion/precursor project  (nycitibike_data_pipeline)[https://github.com/juicero-chief-juice-officer/nycitibike_data_pipeline].

### Slight Tweak to Terraform implementation
In this implementation, we make one tweak to the basic Terraform process. Rather than having a single main.tf, we separate into 2 different "main" runs, each referencing the same set of variables. We might do this for a few different reasons - but here it is because we want to create the service account keys manually after creating service accounts with Terraform. 

In order to facilitate this, we separate our terraform directory as follows:

```
/terraform
├── a1_config_initial_apply
│   └── main.tf
├── a2_config_second_apply
│   └── main.tf
├── terraform.tfvars
└── variables.tf
```

And then, we use symbolic links to tell our system that the variables files in the parent terraform/ directory are actually ALSO in a1_config and a2_config. This code says, in the case of the first line, that the file `a1_config_initial_apply/variables.tf` can be found at `a1_config_initial_apply/../variables.tf`.
```
ln -s ../variables.tf a1_config_initial_apply/variables.tf
ln -s ../variables.tf a2_config_second_apply/variables.tf
ln -s ../terraform.tfvars a1_config_initial_apply/terraform.tfvars
ln -s ../terraform.tfvars a2_config_second_apply/terraform.tfvars
```

### Terraform Structure/Resources
- Service Accounts: The scripts will create a number of service accounts as specified in the svc_accts_and_roles variable in variables.tf. These service accounts allow various services within GCP to authenticate with each other.
- IAM Policy Binding: For each of the created service accounts, the Terraform scripts will set an IAM policy. IAM policies dictate what resources the service accounts have access to and the level of access.
- Cloud Source Repository: In addition to the GitHub repository, a Google Cloud Source repository will also be created. It's another place to store, manage, and track code.
- Cloud Build Trigger: After the repositories are set, a Google Cloud Build Trigger will be created. This will monitor the specified repositories, and if any changes are detected, it will execute a build defined by a provided configuration file.
- Cloud Run Service: A Google Cloud Run Service will be set up. This service allows you to run your applications in a fully managed environment and invoke them via HTTP requests. It will use the container specified in the provided Dockerfile.
- Cloud Scheduler Job: Lastly, a Google Cloud Scheduler Job will be created. This job will execute HTTP requests to a specified endpoint at set intervals.

- GitHub Repository: Using the GitHub provider, a GitHub repository will be created. This repository can be used to store, manage, and track code.

With Terraform, we build as follows: 
1. Service Accounts (Resource: `google_service_account` in main1.tf):
Service accounts allow services to authenticate with each other within a Google Cloud environment. Each service account is defined by the google_service_account resource. Service accounts are identified by email addresses, which are generated by Google and are unique to the account.

2. IAM Policy Binding (Resource: google_service_account_iam_binding in main1.tf):
Set the permissions/access "policy" for each service account. Points to specific GCP resources with specific access levels, and/or roles (combinations of resource access levels). One service account will likely be granted multiple. 

3. Cloud Build Connection to GitHub Repository (Resource: github_repository in main2.tf):
Connects to GitHub repositories, using a secret copy of the GH Personal Access Token stored in GCP by main1.tf (that secret remains only in GCP, and we access it by ID, knowing that the service account is permitted to do so.) 

4. Cloud Source Repository (Resource: google_sourcerepo_repository in main2.tf):
Stores the latest copy of the GH Repo in GCP. 

Set up note:
- If you have not updated your GCP to work out of Artifact Registry, rather than Container Registry. Do so by making sure you have ensure gcloud alpha updates is installed and running:
`gcloud beta artifacts settings enable-upgrade-redirection --project=sbh-nycitibike-pipeline-main`. This will make gcr.io point to Artifacts Registry, as Container Registry will soon be deprecated. 

5. Cloud Build Trigger (Resource: google_cloudbuild_trigger in main2.tf):
With the repositories set, a Google Cloud Build Trigger monitors the specified repositories (`repository_event_config`), and if any changes are detected, it will execute a build defined within the resource. This is contained in the `build` argument, which describes building, tagging, and pushing to the registry the image container. Within build, we can also specific the subdirectory that our Docker files are in. (Note that build steps include a series of arguments that would typically be concatenated by a space: `args = ['echo','hello','world']`.)

6. Cloud Run Service (Resource: google_cloud_run_service in main2.tf):

This is the compute platform that runs containers that are invocable via HTTP requests. The `template` should point to the tag given the image in our trigger's build step.

7. Cloud Scheduler Job (Resource: google_cloud_scheduler_job in main2.tf):
Finally, we create a Cron job to make an http request, invoking a Cloud Run service specified in the `http_target` argument. This will run dbt and update all tables/models. 

8. Bigquery Datasets and Tables (Resource: nested_datasets, external_tables_nested in main):
Finally, we create our datasets and basic (source/raw) tables. With Terraform, it's easy to loop through a set of tables. 

Also ensure you have added cloud build to github
ensure you have gcloud alpha updates installed 
gcloud beta artifacts settings enable-upgrade-redirection \
    --project=sbh-nycitibike-pipeline-main      

## 5. Build basic dbt structure
We have a couple basic files outlining our dbt instance. 

### profiles.yml:
Holds the (literal) key to the BIgQuery data warehouse, and tells dbt how to communicate with it. 

Describes a default profile, and then two output targets (one for each environment), including default DEV, and any environment specific settings. 

### dbt_project.yml:
This is sort of an architectural schematic for dbt, telling it where to find everything it needs and giving it specific instructions on how to handle certain situations. The source-paths, analysis-paths, test-paths, seed-paths, macro-paths, and snapshot-paths describe the locations for those pieces. 

`seeds` specifies the schema for seed files, which are generally smaller, static, often dimensions files, and also enforces column data types.

Finally we include the models structure. In our case, we match (a) the models folder/file structure/naming, (b) the dbt_project.yml models structure, AND (c) the BigQuery dataset names *excepting the environment prefix*. 

### packages.yml
Contains the dbt packages we want. To start, we will just include the basic dbt_utils package. We should set this up by running `dbt deps`. 
