pipeline {
    agent any

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

        stage('Terraform Destroy') {
            steps {
                dir('terraform') {
                    // MUDADO PARA DESTROY
                    sh 'terraform destroy -auto-approve' 
                }
            }
        }
    }

    // O bloco post deve ficar FORA do stages, mas DENTRO do pipeline
    post {
        failure {
            echo 'Ocorreu um erro na destruição da infraestrutura!'
        }
        success {
            echo 'Infraestrutura destruída com sucesso. Economia garantida!'
        }
    }
}