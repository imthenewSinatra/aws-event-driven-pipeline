🚀 AWS Event-Driven Pipeline: Order Processing with CI/CD
This project implements a Serverless Event-Driven Architecture on AWS for asynchronous order processing. It leverages Infrastructure as Code (IaC) with Terraform and a robust CI/CD pipeline via Jenkins to automate the entire lifecycle, from deployment to cleanup.

🏗️ System Architecture
The solution is designed to ensure data integrity and automatic scalability:

AWS API Gateway (REST): Acts as the entry point for incoming order requests.

Amazon SQS FIFO Queue: Ensures that orders are processed in the exact order they arrive and prevents message duplication.

AWS Lambda (Python 3.12): A serverless compute function that validates and processes order data.

Amazon DynamoDB: A NoSQL database where processed orders are persisted with a PROCESSED status.

SQS DLQ (Dead Letter Queue): An isolation queue for messages that fail processing, allowing for later analysis and system resilience.

🛠️ Engineering Highlights
This project goes beyond basic functionality, implementing advanced engineering principles:

Continuous Deployment Synchronization: Utilizes source_code_hash in Terraform to ensure that any change in the Python script triggers an automatic Lambda update.

Security & IAM Roles: Implements the principle of least privilege. The Jenkins server uses an IAM Role attached to the EC2 instance, eliminating the need for hardcoded credentials (AWS Access Keys) in the codebase.

FinOps & Cost Optimization: The Jenkins pipeline includes automated Terraform Destroy stages, enabling a full teardown of the infrastructure after testing to minimize AWS costs.

State Management: Uses an S3 Backend for Terraform state storage, ensuring secure collaboration and state persistence.

🔍 Case Study: Troubleshooting & Debugging
A key highlight of this project was resolving a critical integration error identified through CloudWatch Logs:

Problem: KeyError: 'detail' at line 15 of the Lambda processor.

Diagnosis: The code was expecting an EventBridge event schema, but the actual trigger was SQS, which encapsulates the payload within record['body'].

Resolution: Refactored the data parsing to extract the JSON directly from the SQS body. This was successfully validated with a stress test of 10 simultaneous orders.

📦 Getting Started
Prerequisites: Terraform, AWS CLI, and Jenkins running on an EC2 instance.

Deployment:

Push changes to the repository.

Jenkins automatically triggers the declarative pipeline (init, plan, apply).

Testing: Send a POST request to the API Gateway endpoint and verify the persistence in the DynamoDB table.

👤 About the Author
Affonso Souza Senior IT Infrastructure Specialist with over 10 years of experience, currently specializing in Cloud, DevOps, and Data Science.

AWS Certified: Solutions Architect Associate, Developer Associate, and Cloud Practitioner.

Core Skills: Python, SQL, Terraform, Jenkins, and Cloud Architecture.

Philosophy: Building antifragile and automated environments.