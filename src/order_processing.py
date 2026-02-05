import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ['DYNAMODB_TABLE']

def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)
    
    for record in event['Records']:
        try:
            # O SQS entrega seu JSON como uma string dentro de 'body'
            order_data = json.loads(record['body'])
            
            # REMOVIDO: order_data = order_event['detail'] 
            # O dado agora é extraído diretamente
            
            print(f"Processing order: {order_data.get('orderId', 'Unknown')}")
            
            # Adiciona o status e salva no DynamoDB
            order_data['status'] = 'PROCESSED'
            table.put_item(Item=order_data)
            
            print(f"Order {order_data.get('orderId')} saved successfully.")
            
        except Exception as e:
            print(f"Error processing order: {str(e)}")
            raise e