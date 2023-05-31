## NOTE!
# This is not used, and only remains for reference. 

variable "project" {
  description = "The project id to enable APIs for"
  type        = string
}

variable "apis_to_enable" {
  description = "List of APIs to enable"
  type        = list(string)
}

resource "google_project_service" "project" {
  for_each = toset(var.apis_to_enable)

  project = var.project
  service = each.value

  disable_dependent_services = true
}
