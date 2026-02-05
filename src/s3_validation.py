import json
import boto3
import os

s3 = boto3.client('s3')
sqs = boto3.client('sqs')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

TABLE_NAME = os.environ['DYNAMODB_TABLE']
SNS_ARN = os.environ['SNS_TOPIC_ARN']
SQS_FIFO_URL = os.environ['SQS_FIFO_URL']

def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)
    
    for record in event['Records']:
        try:
            # Get S3 info from SQS message
            s3_event = json.loads(record['body'])
            bucket = s3_event['Records'][0]['s3']['bucket']['name']
            key = s3_event['Records'][0]['s3']['object']['key']
            
            # Download file from S3
            response = s3.get_object(Bucket=bucket, Key=key)
            content = json.loads(response['Body'].read().decode('utf-8'))
            
            # Simple validation and forward to Main FIFO Queue
            for order in content.get('orders', []):
                sqs.send_message(
                    QueueUrl=SQS_FIFO_URL,
                    MessageBody=json.dumps(order),
                    MessageGroupId='s3_batch_group'
                )
            
            # Log success to DynamoDB
            table.put_item(Item={'fileName': key, 'status': 'PROCESSED'})
            
        except Exception as e:
            print(f"Error processing file: {str(e)}")
            # Notify via SNS on failure
            sns.publish(
                TopicArn=SNS_ARN,
                Message=f"Critical error processing file {key}: {str(e)}",
                Subject="S3 Order Ingestion Error"
            )
            table.put_item(Item={'fileName': key, 'status': 'ERROR'})