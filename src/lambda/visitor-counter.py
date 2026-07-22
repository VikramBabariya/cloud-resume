import json
import boto3
import logging

# 1. Setup standard logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize the database connection
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('visitor_count')

def lambda_handler(event, context):
    try:
        log_data = {
            "level": "INFO",
            "message": "Fetching visitor count",
            "request_id": context.aws_request_id
        }
        print(json.dumps(log_data)) # This prints a JSON object to CloudWatch

        # 1. Get the current count and increment it by 1 atomically
        response = table.update_item(
            Key={'id': 'page_view_count'},
            UpdateExpression='SET visitors = visitors + :val',
            ExpressionAttributeValues={':val': 1},
            ReturnValues='UPDATED_NEW'
        )
        
        # 2. Get the new count value
        new_count = response['Attributes']['visitors']

        print(json.dumps({"level": "INFO", "message": "Count updated", "new_count": new_count}, default=str))
        
        # 3. Return it to the browser (with CORS headers)
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
            },
            'body': json.dumps({'count': int(new_count)})
        }
    except Exception as e:
        print(json.dumps({"level": "ERROR", "message": str(e)}))
        raise e