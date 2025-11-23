import json
import os
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import documentai_v1 as documentai

PROJECT_ID = os.environ.get("PROJECT_ID")
DATASET_ID = os.environ.get("DATASET_ID", "data_lake")
TABLE_ID = os.environ.get("TABLE_ID", "finance_docs")

def load_to_bq(cloud_event):
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]

    # Document AI Batch output is sharded. We only want to trigger on the actual JSONs.
    if not file_name.endswith(".json"):
        return

    print(f"Processing result file: {file_name}")

    # 1. Download the JSON result from GCS
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    json_content = blob.download_as_string()

    # Parse into Document AI Object to make traversal easy
    doc = documentai.Document.from_json(json_content)

    # 2. Extract "Golden Columns" (Structured Data)
    # We look for specific entities we trained the processor on
    extracted_data = {
        "file_name": file_name,
        "processed_timestamp": "AUTO", # BQ will handle this or use current time
        "invoice_id": None,
        "total_amount": None,
        "vendor_name": None,
        "confidence_score": 0.0
    }

    # Basic logic to find specific entities
    # In a real scenario, you might map these dynamically
    total_conf = 0
    count = 0

    for entity in doc.entities:
        type_ = entity.type_
        value = entity.mention_text
        conf = entity.confidence

        total_conf += conf
        count += 1

        if type_ == "invoice_id":
            extracted_data["invoice_id"] = value
        elif type_ == "total_amount":
            # Clean currency symbols
            try:
                extracted_data["total_amount"] = float(value.replace('$','').replace(',',''))
            except:
                pass
        elif type_ == "supplier_name":
            extracted_data["vendor_name"] = value

    if count > 0:
        extracted_data["confidence_score"] = total_conf / count

    # 3. The Safety Net: Raw Data
    # We convert the ENTIRE Document AI object (entities, pages, text) back to a dict
    # This goes into the JSON column
    extracted_data["raw_data"] = json.loads(json_content)

    # 4. Insert into BigQuery
    bq_client = bigquery.Client()
    table_ref = f"{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}"

    # For BQ JSON columns, we pass the dict. The client handles serialization.
    rows_to_insert = [extracted_data]

    errors = bq_client.insert_rows_json(table_ref, rows_to_insert)

    if errors:
        print(f"Errors: {errors}")
        # If insert fails, maybe write to a 'failed_inserts' bucket for replay
    else:
        print("Data loaded successfully with JSON safety net.")
