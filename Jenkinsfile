pipeline {
    agent {
        kubernetes {
            yaml '''
                apiVersion: v1
                kind: Pod
                spec:
                  containers:
                  - name: rust
                    image: rust:1-bullseye
                    imagePullPolicy: IfNotPresent
                    command:
                    - cat
                    tty: true
                    resources:
                      requests:
                        memory: "2Gi"
                        cpu: "1000m"
                      limits:
                        memory: "4Gi"
                        cpu: "2000m"
                    volumeMounts:
                    - name: cargo-cache
                      mountPath: /home/jenkins/.cargo
                    - name: rustup-cache
                      mountPath: /home/jenkins/.rustup
                  - name: node
                    image: node:18
                    imagePullPolicy: IfNotPresent
                    command:
                    - cat
                    tty: true
                    volumeMounts:
                    - name: npm-cache
                      mountPath: /root/.npm
                  - name: kaniko
                    image: gcr.io/kaniko-project/executor:latest
                    imagePullPolicy: IfNotPresent
                    command:
                    - /busybox/cat
                    tty: true
                  volumes:
                  - name: cargo-cache
                    persistentVolumeClaim:
                      claimName: cargo-cache-pvc
                  - name: rustup-cache
                    persistentVolumeClaim:
                      claimName: rustup-cache-pvc
                  - name: npm-cache
                    persistentVolumeClaim:
                      claimName: npm-cache-pvc
            '''
            defaultContainer 'rust'
        }
    }

    environment {
        DOCKER_REGISTRY = "${env.DOCKER_REGISTRY}"
        CARGO_HOME = "/home/jenkins/.cargo"
        RUSTUP_HOME = "/home/jenkins/.rustup"
        IMAGE_NAME = 'zkwasm-server'
        IMAGE_TAG = "${BUILD_NUMBER}"
        CUSTOMER_ID = "${params.CUSTOMER_ID}"
        NAMESPACE = "zkwasm-${CUSTOMER_ID}"
        FULL_IMAGE_NAME = "${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        GIT_URL = "${params.GIT_URL}"
        APP_NAME = "${params.APP_NAME}"
        MINIROLLUP_CHARTS_REPO = "${params.MINIROLLUP_CHARTS_REPO}"
    }

    stages {
        stage('Checkout') {
            steps {
                cleanWs()
                git url: '${GIT_URL}',
                    branch: 'main'
            }
        }

        stage('Setup Rust Environment') {
            steps {
                sh '''
                    # 先安装必要的工具
                    apt-get update && apt-get install -y curl build-essential

                    if [ -f "rust-toolchain" ]; then
                        echo "Found rust-toolchain file:"
                        cat rust-toolchain
                        # 可以选择删除或更新这个文件
                        rm rust-toolchain
                        # echo "nightly-2024-01-01" > rust-toolchain
                    fi
                    
                    # 验证版本
                    rustc --version
                    cargo --version
                    g++ --version
                '''
            }
        }

        stage('Install Tools') {
            steps {
                sh '''
                    . "$CARGO_HOME/env"
                    cargo install wasm-pack --locked
                    cargo install wasm-opt --locked
                '''
                // 安装 Node.js 和 npm
                sh '''
                    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
                    apt-get install -y nodejs
                '''
            }
        }

        stage('Build TypeScript') {
            steps {
                container('node') {
                    dir('ts') {
                        sh '''
                            npm ci --verbose
                            npx tsc
                        '''
                    }
                }
            }
        }

        stage('Build Rust') {
            steps {
                sh '''
                    . "$CARGO_HOME/env"
                    wasm-pack build --release --out-name application --out-dir pkg
                    wasm-opt -Oz -o ts/node_modules/zkwasm-ts-server/src/application/application_bg.wasm pkg/application_bg.wasm
                    cp pkg/application_bg.wasm.d.ts ts/node_modules/zkwasm-ts-server/src/application/
                '''
            }
        }

        stage('Archive Artifacts') {
            steps {
                archiveArtifacts artifacts: 'ts/node_modules/zkwasm-ts-server/src/application/application_bg.wasm', 
                                fingerprint: true, 
                                allowEmptyArchive: false,
                                onlyIfSuccessful: true
            }
        }

        stage('Build Docker Image') {
            steps {
                container('kaniko') {
                    sh """
                        /kaniko/executor \
                            --context=. \
                            --dockerfile=./deploy/service.docker \
                            --destination=${FULL_IMAGE_NAME} \
                            --insecure \
                            --skip-tls-verify
                    """
                }
            }
        }

        stage('Deploy to K8s') {
            steps {
                script {
                    // 创建命名空间
                    sh """
                        kubectl create namespace ${NAMESPACE}-${APP_NAME} --dry-run=client -o yaml | kubectl apply -f -
                    """

                    // 克隆包含 charts 的仓库
                    sh """
                        git clone ${MINIROLLUP_CHARTS_REPO} minirollup-charts
                    """

                    // 部署 zkwasm-mini-rollup
                    sh """
                        helm upgrade --install zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME} \
                            --namespace ${NAMESPACE}-${APP_NAME} \
                            --set customerID=${CUSTOMER_ID} \
                            --set appName=${APP_NAME} \
                            --set serviceName=zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME} \
                            ./minirollup-charts/charts
                    """

                    // 创建 ConfigMap 存储构建后的文件
                    sh """
                        kubectl create configmap app-files-${BUILD_NUMBER} \
                            --from-file=ts/src/ \
                            --from-file=pkg/ \
                            -n ${NAMESPACE}-${APP_NAME} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        # 部署主应用
                        cat <<EOF | kubectl apply -f -
                        apiVersion: apps/v1
                        kind: Deployment
                        metadata:
                          name: zkwasm-server-${CUSTOMER_ID}-${APP_NAME}
                          namespace: ${NAMESPACE}-${APP_NAME}
                        spec:
                          replicas: 1
                          selector:
                            matchLabels:
                              app: zkwasm-server-${CUSTOMER_ID}-${APP_NAME}
                          template:
                            metadata:
                              labels:
                                app: zkwasm-server-${CUSTOMER_ID}-${APP_NAME}
                            spec:
                              containers:
                              - name: app
                                image: node:18-slim
                                command:
                                - node
                                - /app/ts/src/service.js
                                env:
                                - name: MINIROLLUP_SERVICE
                                  value: "http://zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME}:3030"
                                volumeMounts:
                                - name: app-files
                                  mountPath: /app
                              volumes:
                              - name: app-files
                                configMap:
                                  name: app-files-${BUILD_NUMBER}
                        ---
                        apiVersion: v1
                        kind: Service
                        metadata:
                          name: zkwasm-server-${CUSTOMER_ID}-${APP_NAME}
                          namespace: ${NAMESPACE}-${APP_NAME}
                        spec:
                          selector:
                            app: zkwasm-server-${CUSTOMER_ID}-${APP_NAME}
                          ports:
                          - port: 3000
                            targetPort: 3000
                        EOF
                    """
                }
            }
        }
    }
}