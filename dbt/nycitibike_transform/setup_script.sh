#!/bin/sh
# simple script to tell gcp what dbt commands should be run
# --profiles-dir is needed as dbt usually looks for profiles.yml in ~/.dbt/
dbt deps --profiles-dir .  # Pulls the most recent version of the dependencies listed in your packages.yml from git
dbt debug --target dev --profiles-dir .
dbt debug --target prod --profiles-dir .
dbt run --target prod --profiles-dir .
dbt test --data --target dev --profiles-dir .