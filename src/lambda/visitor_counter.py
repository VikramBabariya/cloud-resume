import json
import os
import boto3
import logging

# Use the logging module per project code style (not print)
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Read table name from the environment variable injected by Terraform.
# Falling back to a hardcoded default is intentionally omitted — if the
# env var is missing the function should fail loudly at init time, not
# silently hit a wrong table.
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]

# Initialize the DynamoDB resource at module level (reused across invocations)
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def lambda_handler(event, context):
    try:
        logger.info(
            json.dumps(
                {
                    "message": "Fetching visitor count",
                    "request_id": context.aws_request_id,
                    "table": TABLE_NAME,
                }
            )
        )

        # Atomically increment the visitor counter and return the new value
        response = table.update_item(
            Key={"id": "page_view_count"},
            UpdateExpression="SET visitors = if_not_exists(visitors, :zero) + :val",
            ExpressionAttributeValues={":val": 1, ":zero": 0},
            ReturnValues="UPDATED_NEW",
        )

        new_count = response["Attributes"]["visitors"]

        logger.info(
            json.dumps(
                {
                    "message": "Count updated",
                    "new_count": str(new_count),
                }
            )
        )

        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "https://vikram-sre.dev",
                "Access-Control-Allow-Headers": "Content-Type",
                "Access-Control-Allow-Methods": "OPTIONS,POST",
            },
            "body": json.dumps({"count": int(new_count)}),
        }

    except Exception as e:
        logger.error(json.dumps({"message": "Unhandled exception", "error": str(e)}))
        raise