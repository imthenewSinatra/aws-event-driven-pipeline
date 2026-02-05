import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ['DYNAMODB_TABLE']

def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)
    
    for record in event['Records']:
        try:
            # The event comes from EventBridge through SQS
            order_event = json.loads(record['body'])
            order_data = order_event['detail']
            
            print(f"Processing order: {order_data['orderId']}")
            
            # Simulate final processing logic (Inventory, Shipping, etc.)
            order_data['status'] = 'PROCESSED'
            
            # Save to the main DynamoDB table
            table.put_item(Item=order_data)
            print(f"Order {order_data['orderId']} saved successfully.")
            
        except Exception as e:
            print(f"Error processing order: {str(e)}")
            raise e