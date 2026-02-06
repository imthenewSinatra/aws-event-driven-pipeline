import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ['DYNAMODB_TABLE']

def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)
    
    for record in event['Records']:
        try:
            # SQS delivers your JSON as a string within 'body'
            order_data = json.loads(record['body'])
            
            print(f"Processing order: {order_data.get('orderId', 'Unknown')}")
            
            # Add the status and save it to DynamoDB
            order_data['status'] = 'PROCESSED'
            table.put_item(Item=order_data)
            
            print(f"Order {order_data.get('orderId')} saved successfully.")
            
        except Exception as e:
            print(f"Error processing order: {str(e)}")
            raise e