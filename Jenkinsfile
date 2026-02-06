pipeline {
    agent any

    environment {
        AWS_CREDENTIALS = credentials('aws-credentials-lab')
        AWS_DEFAULT_REGION = 'us-east-1'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    sh 'terraform plan'
                }
            }
        }

        stage('Terraform Destroy') {
            steps {
                dir('terraform') {
                    sh 'terraform destroy -auto-approve'
                }
            }
        }
    }

 //   post {
 //       always {
 //           cleanWs()
 //       }
        failure {
            echo 'Oops! Build failed. Initiating AWS cleanup to prevent resource conflicts...'
            dir('terraform') {
                sh 'terraform destroy -auto-approve'
            }
        }
    }