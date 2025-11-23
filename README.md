# Unstructured Data Processor

Event-driven pipeline for processing unstructured documents (PDFs, images) using Google Cloud Platform's Document AI, with automatic structured data extraction to BigQuery.

## Architecture

```
Raw Documents (GCS) → Dispatcher Function → Document AI → Loader Function → BigQuery
```

### Components

- **Input Bucket**: Receives raw documents (PDFs, images)
- **Dispatcher Function**: Triggers Document AI batch processing jobs
- **Document AI**: Extracts structured data from documents
- **Output Bucket**: Stores Document AI JSON results
- **Loader Function**: Parses results and loads to BigQuery
- **BigQuery**: Stores structured data with JSON safety net

## Project Structure

```
.
├── infra/                 # Infrastructure as Code
│   ├── main.tf            # Main infrastructure definition
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   ├── versions.tf        # Provider versions
│   └── backend.tf.example # Remote state configuration example
├── src/
│   ├── dispatcher/        # Cloud Function: Document AI dispatcher
│   │   ├── main.py
│   │   └── requirements.txt
│   └── loader/            # Cloud Function: BigQuery loader
│       ├── main.py
│       └── requirements.txt
├── docs/                  # Documentation
│   └── CLOUDBUILD_DEPLOYMENT.md
├── cloudbuild.yaml        # CI/CD pipeline configuration
└── README.md
```

## Prerequisites

- GCP Project with billing enabled
- `gcloud` CLI installed and authenticated
- Terraform >= 1.5.0

## Quick Start

### 1. Deploy Infrastructure

```bash
# Clone the repository
git clone https://github.com/RomanKaliupinMelonusa/unstructured-data-processor.git
cd unstructured-data-processor

# Deploy with Terraform
cd infra
terraform init
terraform apply -var="project_id=YOUR-PROJECT-ID" -var="region=us-central1"
```

### 2. Upload a Document

```bash
# Get bucket name from Terraform output
BUCKET=$(terraform output -raw input_bucket_name)

# Upload a test document
gsutil cp sample-invoice.pdf gs://${BUCKET}/
```

### 3. View Results

```bash
# Query BigQuery
bq query --use_legacy_sql=false \
  'SELECT * FROM `YOUR-PROJECT-ID.data_lake.finance_docs` LIMIT 10'
```

## Configuration

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP Project ID | Required |
| `region` | GCP Region | `us-central1` |

### Outputs

After deployment, Terraform outputs:
- Input/output bucket names
- BigQuery dataset/table IDs
- Cloud Function URLs
- Service account email

## CI/CD Deployment

See [docs/CLOUDBUILD_DEPLOYMENT.md](docs/CLOUDBUILD_DEPLOYMENT.md) for automated deployment using Cloud Build.

## Features

- ✅ **Event-Driven**: Automatically processes files on upload
- ✅ **Scalable**: Cloud Functions auto-scale based on load
- ✅ **Schema Evolution**: JSON column preserves full Document AI output
- ✅ **Batch Processing**: Cost-effective Document AI batch operations
- ✅ **Fully Portable**: Deploy to any GCP project with one command
- ✅ **Infrastructure as Code**: Complete Terraform automation

## Cost Optimization

- Uses Document AI batch processing (cheaper than online)
- Cloud Functions Gen2 with auto-scaling
- Pay-per-use pricing model
- No idle resource costs

## Monitoring

```bash
# View Cloud Function logs
gcloud functions logs read docai-dispatcher --region=us-central1 --limit=50
gcloud functions logs read bq-loader --region=us-central1 --limit=50

# Monitor BigQuery inserts
bq query --use_legacy_sql=false \
  'SELECT COUNT(*) as total_documents FROM `YOUR-PROJECT-ID.data_lake.finance_docs`'
```

## Cleanup

```bash
cd infra
terraform destroy -var="project_id=YOUR-PROJECT-ID"
```

## License

MIT License - see LICENSE file for details.
