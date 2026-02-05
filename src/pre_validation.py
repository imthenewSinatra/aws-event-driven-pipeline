import json
import os
import boto3

sqs = boto3.client('sqs')
QUEUE_URL = os.environ['SQS_QUEUE_URL']

def lambda_handler(event, context):
    print(f"Event received: {json.dumps(event)}")
    
    try:
        body = json.loads(event['body'])
        
        # Validate required fields
        if not body.get('orderId') or not body.get('clientId'):
            return {
                'statusCode': 400,
                'body': json.dumps({'message': 'Missing orderId or clientId'})
            }
        
        # Send message to the FIFO queue
        response = sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(body),
            MessageGroupId='orders_group'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Order received and queued',
                'messageId': response['MessageId']
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'message': 'Internal Server Error'})
        }