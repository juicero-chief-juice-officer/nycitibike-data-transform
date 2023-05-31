#!/bin/bash
ln -s ../variables.tf a1_config_initial_apply/variables.tf
ln -s ../variables.tf a2_config_second_apply/variables.tf
ln -s ../terraform.tfvars a2_config_second_apply/terraform.tfvars
ln -s ../terraform.tfvars a2_config_second_apply/terraform.tfvars

cd a1_config_initial_apply
terraform init
terraform apply -auto-approve

cd ../a2_config_second_apply
terraform init
terraform apply -auto-approve
