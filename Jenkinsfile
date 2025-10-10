pipeline {
    agent any
    environment {
        PATH = "$PATH:/opt/3.32.0/bin:/opt" 
    }
    parameters {
        gitParameter branchFilter: 'origin/(.*)', defaultValue: 'main', name: 'BRANCH', type: 'PT_BRANCH'
    }
    stages {
        stage('cloning Repository') {
            steps {
                echo 'Cloning Repo'
                git branch: "${params.BRANCH}", credentialsId: 'ssh-key-github-access', url: 'git@github.com:Oualitsen/Retrofit-Graphql-For-Dart.git'
            }
        }

        stage('pub get') {
            steps {
                echo 'running pub get'
                sh 'dart pub get'
            }
        }
        stage('Test') {
            steps {
                echo 'Running tests'
                sh "dart test"
            }
        }
        stage('build') {
            steps {
                echo " Building ..."
                sh "dart compile exe lib/src/main.dart -o gqlcodegen"
            }
        }

        stage('Deploy') {
            when {
                expression {return params.BRANCH == 'main' || params.BRANCH == 'origin/main'}
            }
            steps {
                echo " Deploying ..."
                sh "sudo cp gqlcodegen /opt"
            }
        }
    }
}