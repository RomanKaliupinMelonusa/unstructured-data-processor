# Cloud Build Deployment Guide

## Prerequisites

### 1. Create Service Account for Cloud Build
```bash
export PROJECT_ID="your-project-id"

# Create service account
gcloud iam service-accounts create cloudbuild-terraform \
    --display-name="Cloud Build Terraform Service Account" \
    --project=${PROJECT_ID}

# Grant necessary roles
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:cloudbuild-terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/editor"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:cloudbuild-terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.securityAdmin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:cloudbuild-terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/serviceusage.serviceUsageAdmin"
```

### 2. (Optional) Set up Remote State Backend
```bash
# Create bucket for Terraform state
gsutil mb -p ${PROJECT_ID} -l us-central1 gs://${PROJECT_ID}-terraform-state

# Enable versioning
gsutil versioning set on gs://${PROJECT_ID}-terraform-state

# Copy example backend config
cp backend.tf.example backend.tf

# Update PROJECT_ID in backend.tf
sed -i "s/REPLACE_WITH_YOUR_PROJECT_ID/${PROJECT_ID}/" backend.tf
```

## Deployment Options

### Option 1: Manual Trigger
```bash
# Submit build manually
gcloud builds submit \
    --config=cloudbuild.yaml \
    --project=${PROJECT_ID} \
    --substitutions=_REGION=us-central1
```

### Option 2: GitHub/Source Repository Trigger
```bash
# Create trigger from GitHub (requires connecting your repo first)
gcloud builds triggers create github \
    --name="terraform-deploy" \
    --repo-name="unstructured-data-processor" \
    --repo-owner="RomanKaliupinMelonusa" \
    --branch-pattern="^main$" \
    --build-config="cloudbuild.yaml" \
    --project=${PROJECT_ID} \
    --substitutions=_REGION=us-central1
```

### Option 3: Cloud Source Repositories Trigger
```bash
# First, mirror your GitHub repo to Cloud Source Repositories
gcloud source repos create unstructured-data-processor --project=${PROJECT_ID}

# Create trigger
gcloud builds triggers create cloud-source-repositories \
    --name="terraform-deploy" \
    --repo="unstructured-data-processor" \
    --branch-pattern="^main$" \
    --build-config="cloudbuild.yaml" \
    --project=${PROJECT_ID} \
    --substitutions=_REGION=us-central1
```

## Customization

### Change Region
Edit `_REGION` substitution in `cloudbuild.yaml` or override during submission:
```bash
gcloud builds submit --substitutions=_REGION=us-east1
```

### Add Terraform Destroy Step
Add to `cloudbuild.yaml`:
```yaml
  # Terraform Destroy (use with caution)
  - name: 'hashicorp/terraform:1.6'
    id: 'terraform-destroy'
    args:
      - 'destroy'
      - '-auto-approve'
      - '-var=project_id=${PROJECT_ID}'
      - '-var=region=${_REGION}'
    env:
      - 'TF_IN_AUTOMATION=true'
    waitFor: ['terraform-plan']
```

## Monitoring
```bash
# View recent builds
gcloud builds list --project=${PROJECT_ID} --limit=10

# Stream logs from specific build
gcloud builds log <BUILD_ID> --stream --project=${PROJECT_ID}
```

## Troubleshooting

### Permission Errors
Ensure the service account has all necessary roles. You may need to add:
- `roles/cloudfunctions.developer`
- `roles/documentai.admin`
- `roles/storage.admin`
- `roles/bigquery.admin`

### State Lock Issues
If using remote state and encountering locks:
```bash
terraform force-unlock <LOCK_ID>
```
