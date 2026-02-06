pipeline {
    agent any

    environment {
        TF_VAR_alert_email = credentials('SNS_ALERT_EMAIL')
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
                    sh 'terraform plan -out=tfplan'
                }
            }
        }

        // NOTE: In a production environment, the 'apply' stage should use the plan 
        // artifact generated in the previous step (e.g., 'terraform apply -auto-approve tfplan').
        // This ensures that exactly what was planned and reviewed is what gets 
        // executed, preventing any drift or unexpected changes between stages.

        // stage('Terraform Apply') {
        //     steps {
        //         dir('terraform') {
        //             sh 'terraform apply -auto-approve' 
        //         }
        //     }
        // }

        // Destroy command
        stage('Terraform Destroy') {
            steps {
                dir('terraform') {
                    sh 'terraform destroy -auto-approve' 
                }
            }
        }
    
    }
    post {
        failure {
            echo 'An error occurred during the destruction of the infrastructure!'
        }
        success {
            echo 'Infrastructure successfully destroyed. Savings guaranteed!'
        }
    }
    // post {
    //     failure {
    //         echo 'An error occurred during the infrastructure destruction!'
    //     }
    //     success {
    //         echo 'Infrastructure successfully destroyed. Savings guaranteed!'
    //     }
    // }
}