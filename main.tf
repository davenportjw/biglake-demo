/**
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

data "google_project" "project" {
  project_id = var.project_id
}

module "project-services" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "14.1"
  disable_services_on_destroy = false

  project_id  = var.project_id
  enable_apis = var.enable_apis

  activate_apis = [
    "compute.googleapis.com",
    "cloudapis.googleapis.com",
    "cloudbuild.googleapis.com",
    "datacatalog.googleapis.com",
    "datalineage.googleapis.com",
    "eventarc.googleapis.com",
    "bigquerymigration.googleapis.com",
    "bigquerystorage.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "bigqueryreservation.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "storage-api.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "cloudfunctions.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "artifactregistry.googleapis.com",
    "config.googleapis.com",
    "dataproc.googleapis.com",
    "biglake.googleapis.com"
  ]
}

# Random ID
resource "random_id" "id" {
  byte_length = 4
}

# Set up networking
resource "google_compute_network" "default_network" {
  project                 = module.project-services.project_id
  name                    = "vpc-${var.use_case_short}"
  description             = "Default network"
  auto_create_subnetworks = false
  mtu                     = 1460
}

resource "google_compute_subnetwork" "subnet" {
  project                  = module.project-services.project_id
  name                     = "dataproc-subnet"
  ip_cidr_range            = "10.3.0.0/16"
  region                   = var.region
  network                  = google_compute_network.default_network.id
  private_ip_google_access = true

  depends_on = [
    google_compute_network.default_network,
  ]
}

# Firewall rule for dataproc cluster
resource "google_compute_firewall" "subnet_firewall_rule" {
  project = module.project-services.project_id
  name    = "dataproc-firewall"
  network = google_compute_network.default_network.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
  source_ranges = ["10.3.0.0/16"]

  depends_on = [
    google_compute_subnetwork.subnet
  ]
}


# Set up Dataproc service account for the Cloud Function to execute as
# # Set up the Dataproc service account
resource "google_service_account" "dataproc_service_account" {
  project      = module.project-services.project_id
  account_id   = "dataproc-sa-${random_id.id.hex}"
  display_name = "Service Account for Dataproc Execution"
}

# # Grant the Dataproc service account Object Create / Delete access
resource "google_project_iam_member" "dataproc_service_account_storage_role" {
  project = module.project-services.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.dataproc_service_account.email}"

  depends_on = [
    google_service_account.dataproc_service_account
  ]
}

# # Grant the Dataproc service account BQ Connection Access
resource "google_project_iam_member" "dataproc_service_account_bq_connection_role" {
  project = module.project-services.project_id
  role    = "roles/bigquery.connectionUser"
  member  = "serviceAccount:${google_service_account.dataproc_service_account.email}"

  depends_on = [
    google_service_account.dataproc_service_account
  ]
}

# # Grant the Dataproc service account BigLake access
resource "google_project_iam_member" "dataproc_service_account_biglake_role" {
  project = module.project-services.project_id
  role    = "roles/biglake.admin"
  member  = "serviceAccount:${google_service_account.dataproc_service_account.email}"

  depends_on = [
    google_service_account.dataproc_service_account
  ]
}

# # Grant the Dataproc service account dataproc access
resource "google_project_iam_member" "dataproc_service_account_dataproc_worker_role" {
  project = module.project-services.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.dataproc_service_account.email}"

  depends_on = [
    google_service_account.dataproc_service_account
  ]
}

# Set up Storage Buckets
# # Set up the export storage bucket
resource "google_storage_bucket" "export_bucket" {
  name                        = "gcp-${var.use_case_short}-export-${random_id.id.hex}"
  project                     = module.project-services.project_id
  location                    = "us-central1"
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy

  # public_access_prevention = "enforced" # need to validate if this is a hard requirement
}

# # Set up the raw storage bucket
resource "google_storage_bucket" "raw_bucket" {
  name                        = "gcp-${var.use_case_short}-raw-${random_id.id.hex}"
  project                     = module.project-services.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy

  # public_access_prevention = "enforced" # need to validate if this is a hard requirement
}

# # Set up the provisioning bucketstorage bucket
resource "google_storage_bucket" "provisioning_bucket" {
  name                        = "gcp-${var.use_case_short}-provisioner-${random_id.id.hex}"
  project                     = module.project-services.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy

  # public_access_prevention = "enforced"
}

# Set up BigQuery resources
# # Create the BigQuery dataset
resource "google_bigquery_dataset" "ds" {
  project                    = module.project-services.project_id
  dataset_id                 = "gcp_${var.use_case_short}"
  friendly_name              = "My Dataset"
  description                = "My Dataset with tables"
  location                   = var.region
  labels                     = var.labels
  delete_contents_on_destroy = var.force_destroy
}

# # Create a BigQuery connection
resource "google_bigquery_connection" "ds_connection" {
  project       = module.project-services.project_id
  connection_id = "gcp_gcs_connection"
  location      = var.region
  friendly_name = "Storage Bucket Connection"
  cloud_resource {}
}

# # Grant IAM access to the BigQuery Connection account for Cloud Storage
resource "google_project_iam_member" "bq_connection_iam_object_viewer" {
  project = module.project-services.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_bigquery_connection.ds_connection.cloud_resource[0].service_account_id}"

  depends_on = [
    google_bigquery_connection.ds_connection
  ]
}

# # Create a BigQuery external table
resource "google_bigquery_table" "tbl_thelook_events" {
  dataset_id          = google_bigquery_dataset.ds.dataset_id
  table_id            = "events"
  project             = module.project-services.project_id
  deletion_protection = var.deletion_protection

  external_data_configuration {
    autodetect    = true
    connection_id = google_bigquery_connection.ds_connection.name #TODO: Change other solutions to remove hardcoded reference
    source_format = "PARQUET"
    source_uris   = ["gs://${var.public_data_bucket}/thelook_ecommerce/events-*.Parquet"]

  }

  schema = <<EOF
[
  {
    "name": "id",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "user_id",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "sequence_number",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "session_id",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "created_at",
    "type": "TIMESTAMP",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "ip_address",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "city",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "postal_code",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "browser",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "traffic_source",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "uri",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": ""
  },
  {
    "name": "event_type",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": ""
  }
]
EOF

  depends_on = [
    google_bigquery_connection.ds_connection,
    google_storage_bucket.raw_bucket
  ]
}

resource "google_storage_bucket_object" "pyspark_file" {
  bucket = google_storage_bucket.provisioning_bucket.name
  name   = "bigquery.py"
  source = "${path.module}/assets/bigquery.py"

  depends_on = [
    google_storage_bucket.provisioning_bucket
  ]

}

# # Load Queries for Stored Procedure Execution
# # # Add Sample Queries
# resource "google_bigquery_routine" "sp_sample_queries" {
#   project         = module.project-services.project_id
#   dataset_id      = google_bigquery_dataset.ds_edw.dataset_id
#   routine_id      = "sp_sample_queries"
#   routine_type    = "PROCEDURE"
#   language        = "SQL"
#   definition_body = templatefile("${path.module}/assets/sql/sp_sample_queries.sql", { project_id = module.project-services.project_id })

#   depends_on = [
#     google_bigquery_table.tbl_edw_taxi,
#   ]
# }

# Set up Workflows service account
# # Set up the Workflows service account
resource "google_service_account" "workflow_service_account" {
  project      = module.project-services.project_id
  account_id   = "cloud-workflow-sa-${random_id.id.hex}"
  display_name = "Service Account for Cloud Workflows"
}

# # Grant the Workflow service account Workflows Admin
resource "google_project_iam_member" "workflow_service_account_invoke_role" {
  project = module.project-services.project_id
  role    = "roles/workflows.admin"
  member  = "serviceAccount:${google_service_account.workflow_service_account.email}"

  depends_on = [
    google_service_account.workflow_service_account
  ]
}

# # Grant the Workflow service account Dataproc admin
resource "google_project_iam_member" "workflow_service_account_dataproc_role" {
  project = module.project-services.project_id
  role    = "roles/dataproc.admin"
  member  = "serviceAccount:${google_service_account.workflow_service_account.email}"

  depends_on = [
    google_service_account.workflow_service_account
  ]
}

# # Grant the Workflow service account BQ admin
resource "google_project_iam_member" "workflow_service_account_bqrole" {
  project = module.project-services.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.workflow_service_account.email}"

  depends_on = [
    google_service_account.workflow_service_account
  ]
}

# # Grant the Workflow service account access to run as other service accounts
resource "google_project_iam_member" "workflow_service_account_token_role" {
  project = module.project-services.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.workflow_service_account.email}"

  depends_on = [
    google_service_account.workflow_service_account
  ]
}

resource "google_workflows_workflow" "workflow" {
  name            = "initial-workflow"
  project         = module.project-services.project_id
  region          = var.region
  description     = "Runs post Terraform setup steps for Solution in Console"
  service_account = google_service_account.workflow_service_account.id
  source_contents = templatefile("${path.module}/workflow.yaml", {
    dataproc_service_account = google_service_account.dataproc_service_account.email,
    provisioner_bucket       = google_storage_bucket.provisioner_bucket.name,
    warehouse_bucket         = google_storage_bucket.raw_bucket.name,
    temp_bucket              = google_storage_bucket.raw_bucket.name
  })

}

resource "google_storage_bucket_object" "startfile" {
  bucket = google_storage_bucket.provisioning_bucket.name
  name   = "startfile"
  source = "${path.module}/assets/startfile"

  depends_on = [
    google_workflows_workflow.workflow,
    google_eventarc_trigger.trigger_pubsub_tf
  ]

}


# Create Eventarc Trigger
// Create a Pub/Sub topic.
resource "google_pubsub_topic" "topic" {
  name    = "provisioning-topic"
  project = module.project-services.project_id
}

data "google_storage_project_service_account" "gcs_account" {
  project = module.project-services.project_id
}

resource "google_pubsub_topic_iam_binding" "binding" {
  project = module.project-services.project_id
  topic   = google_pubsub_topic.topic.id
  role    = "roles/pubsub.publisher"
  members = ["serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"]
}

resource "google_storage_notification" "notification" {
  provider       = google
  bucket         = google_storage_bucket.provisioning_bucket.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.topic.id
  depends_on     = [google_pubsub_topic_iam_binding.binding]
}

resource "google_eventarc_trigger" "trigger_pubsub_tf" {
  project  = module.project-services.project_id
  name     = "trigger-pubsub-tf"
  location = var.region
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"


  }
  destination {
    workflow = google_workflows_workflow.workflow.id
  }

  transport {
    pubsub {
      topic = google_pubsub_topic.topic.id
    }
  }
  service_account = google_service_account.eventarc_service_account.email

  depends_on = [
    google_workflows_workflow.workflow,
    google_project_iam_member.eventarc_service_account_invoke_role
  ]
}

# Set up Eventarc service account for the Cloud Function to execute as
# # Set up the Eventarc service account
resource "google_service_account" "eventarc_service_account" {
  project      = module.project-services.project_id
  account_id   = "eventarc-sa-${random_id.id.hex}"
  display_name = "Service Account for Cloud Eventarc"
}

# # Grant the Eventar service account Workflow Invoker Access
resource "google_project_iam_member" "eventarc_service_account_invoke_role" {
  project = module.project-services.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.eventarc_service_account.email}"

  depends_on = [
    google_service_account.eventarc_service_account
  ]
}