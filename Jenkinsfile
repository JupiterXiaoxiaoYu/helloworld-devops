pipeline {
    agent {
        kubernetes {
            yaml '''
                apiVersion: v1
                kind: Pod
                metadata:
                  labels:
                    jenkins: worker
                spec:
                  serviceAccountName: jenkins-deployer
                  containers:
                  - name: docker
                    image: docker:dind
                    securityContext:
                      privileged: true
                    volumeMounts:
                      - name: docker-sock
                        mountPath: /var/run/docker.sock
                  - name: kubectl
                    image: alpine/k8s:1.24.13
                    imagePullPolicy: IfNotPresent
                    command:
                    - cat
                    tty: true
                  volumes:
                  - name: docker-sock
                    hostPath:
                      path: /var/run/docker.sock
            '''
            defaultContainer 'kubectl'
        }
    }

    environment {
        IMAGE_NAME = 'zkwasm-server'
        IMAGE_TAG = "${BUILD_NUMBER}"
        CUSTOMER_ID = "${params.CUSTOMER_ID}"
        NAMESPACE = "zkwasm-${CUSTOMER_ID}"
        FULL_IMAGE_NAME = "${IMAGE_NAME}:${IMAGE_TAG}"
        GIT_URL = "${params.GIT_URL}"
        APP_NAME = "${params.APP_NAME}"
        MINIROLLUP_CHARTS_REPO = "${params.MINIROLLUP_CHARTS_REPO}"
        RELEASE_NAME = "zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME}"
    }

    stages {

        stage('Debug Docker') {
            steps {
                container('docker') {
                    sh '''
                        # 检查 Docker 环境
                        ls -l /var/run/docker.sock
                        docker info
                        docker ps
                    '''
                }
            }
        }

        stage('Deploy to K8s') {
            options {
                timeout(time: 15, unit: 'MINUTES')
            }
            steps {
                container('kubectl') {
                    sh '''
                        # 检查命名空间是否存在
                        echo "Adding Helm repository..."
                        helm repo add zkwasm-charts ${MINIROLLUP_CHARTS_REPO}
                        
                        echo "Updating Helm repository..."
                        helm repo update
                        
                        echo "Checking Helm chart..."
                        helm search repo zkwasm-charts/zkwasm-service

                        if kubectl get namespace ${NAMESPACE}-${APP_NAME} >/dev/null 2>&1; then
                            echo "Namespace ${NAMESPACE}-${APP_NAME} exists, checking deployment status..."
                            
                            # 检查 Helm release 是否存在
                            if helm status zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME} -n ${NAMESPACE}-${APP_NAME} >/dev/null 2>&1; then
                                echo "Checking services status..."
                                
                                # 检查各个服务的状态
                                MONGODB_READY=$(kubectl get pods -n ${NAMESPACE}-${APP_NAME} -l app=${RELEASE_NAME}-mongodb -o jsonpath='{.items[*].status.phase}' | grep -c "Running" || true)
                                REDIS_READY=$(kubectl get pods -n ${NAMESPACE}-${APP_NAME} -l app=${RELEASE_NAME}-redis -o jsonpath='{.items[*].status.phase}' | grep -c "Running" || true)
                                MERKLE_READY=$(kubectl get pods -n ${NAMESPACE}-${APP_NAME} -l app=${RELEASE_NAME}-merkleservice -o jsonpath='{.items[*].status.phase}' | grep -c "Running" || true)
                                
                                echo "Current service status:"
                                echo "MongoDB Pods: $MONGODB_READY"
                                echo "Redis Pods: $REDIS_READY"
                                echo "Merkle Service Pods: $MERKLE_READY"
                                
                                # 检查并启动未运行的服务
                                if [ "$MONGODB_READY" -eq 0 ]; then
                                    echo "MongoDB is not running, starting MongoDB..."
                                    helm upgrade --install zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME} \
                                        --namespace ${NAMESPACE}-${APP_NAME} \
                                        --set mongodb.enabled=true \
                                        --set redis.enabled=false \
                                        --set merkleservice.enabled=false \
                                        zkwasm-charts/zkwasm-service
                                    
                                    echo "Waiting for MongoDB to be ready..."
                                    kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-mongodb -n ${NAMESPACE}-${APP_NAME} --timeout=5m
                                fi
                                
                                if [ "$REDIS_READY" -eq 0 ]; then
                                    echo "Redis is not running, starting Redis..."
                                    helm upgrade --install zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME} \
                                        --namespace ${NAMESPACE}-${APP_NAME} \
                                        --set mongodb.enabled=false \
                                        --set redis.enabled=true \
                                        --set merkleservice.enabled=false \
                                        zkwasm-charts/zkwasm-service
                                    
                                    echo "Waiting for Redis to be ready..."
                                    kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-redis -n ${NAMESPACE}-${APP_NAME} --timeout=5m
                                fi
                                
                                if [ "$MERKLE_READY" -eq 0 ]; then
                                    echo "Merkle service is not running, checking deployment..."
                                    
                                    DEPLOYMENT_NAME=${RELEASE_NAME}-merkleservice
                                    
                                    # 检查 deployment 是否存在
                                    if ! kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE}-${APP_NAME} >/dev/null 2>&1; then
                                        echo "Merkle service deployment not found, creating..."
                                        
                                        # 使用 helm 创建服务
                                        helm upgrade --install zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME} \
                                            --namespace ${NAMESPACE}-${APP_NAME} \
                                            --set mongodb.enabled=false \
                                            --set redis.enabled=false \
                                            --set merkleservice.enabled=true \
                                            --set mongodb.persistence.size=5Gi \
                                            zkwasm-charts/zkwasm-service
                                    else
                                        echo "Merkle service deployment found, restarting..."
                                        kubectl rollout restart deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE}-${APP_NAME}
                                    fi
                                    
                                    echo "Waiting for Merkle service to be ready..."
                                    kubectl wait --for=condition=ready pod -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE}-${APP_NAME} --timeout=5m
                                fi
                                
                                # 再次检查所有服务状态
                                echo "Verifying all services..."
                                kubectl get pods -n ${NAMESPACE}-${APP_NAME}
                                
                                # 如果所有服务都在运行，则退出
                                MONGODB_READY=$(kubectl get pods -n ${NAMESPACE}-${APP_NAME} -l app=${RELEASE_NAME}-mongodb -o jsonpath='{.items[*].status.phase}' | grep -c "Running" || true)
                                REDIS_READY=$(kubectl get pods -n ${NAMESPACE}-${APP_NAME} -l app=${RELEASE_NAME}-redis -o jsonpath='{.items[*].status.phase}' | grep -c "Running" || true)
                                MERKLE_READY=$(kubectl get pods -n ${NAMESPACE}-${APP_NAME} -l app=${RELEASE_NAME}-merkleservice -o jsonpath='{.items[*].status.phase}' | grep -c "Running" || true)
                                
                                if [ "$MONGODB_READY" -gt 0 ] && [ "$REDIS_READY" -gt 0 ] && [ "$MERKLE_READY" -gt 0 ]; then
                                    echo "All services are now running."
                                    exit 0
                                fi
                            fi
                        fi
                        
                        echo "Services not found or not running properly, proceeding with deployment..."

                        
                        echo "Installing Helm chart (debug mode)..."
                        helm upgrade --install zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME} \
                            --namespace ${NAMESPACE}-${APP_NAME} \
                            --create-namespace \
                            --set customerID=${CUSTOMER_ID} \
                            --set appName=${APP_NAME} \
                            --set serviceName=${RELEASE_NAME} \
                            --set mongodb.persistence.size=5Gi \
                            --set resources.requests.memory=1Gi \
                            --set resources.limits.memory=2Gi \
                            --timeout 15m \
                            --debug \
                            --dry-run \
                            zkwasm-charts/zkwasm-service
                            
                        echo "Proceeding with actual installation..."
                        helm upgrade --install zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME} \
                            --namespace ${NAMESPACE}-${APP_NAME} \
                            --create-namespace \
                            --set customerID=${CUSTOMER_ID} \
                            --set appName=${APP_NAME} \
                            --set serviceName=${RELEASE_NAME} \
                            --set mongodb.persistence.size=5Gi \
                            --set resources.requests.memory=1Gi \
                            --set resources.limits.memory=2Gi \
                            --timeout 15m \
                            zkwasm-charts/zkwasm-service
                            
                        echo "Waiting for pods to be created..."
                        sleep 10
                        
                        echo "Checking pod status..."
                        kubectl get pods -n ${NAMESPACE}-${APP_NAME}
                        
                        # 分别等待每个服务就绪
                        function wait_for_pod() {
                            local label=$1
                            local namespace=$2
                            local timeout=$3
                            echo "Waiting for pod with label $label in namespace $namespace..."
                            kubectl wait --for=condition=ready pod -l $label -n $namespace --timeout=$timeout || true
                            kubectl get pods -l $label -n $namespace
                        }

                        echo "Waiting for MongoDB..."
                        wait_for_pod "app=${RELEASE_NAME}-mongodb" "${NAMESPACE}-${APP_NAME}" "5m"
                        
                        echo "Waiting for Redis..."
                        wait_for_pod "app=${RELEASE_NAME}-redis" "${NAMESPACE}-${APP_NAME}" "5m"
                        
                        echo "Waiting for Merkle service..."
                        wait_for_pod "app=${RELEASE_NAME}-merkleservice" "${NAMESPACE}-${APP_NAME}" "5m"
                        
                        echo "Final status check..."
                        kubectl get all -n ${NAMESPACE}-${APP_NAME}
                    '''
                }
            }
            post {
                success {
                    container('kubectl') {
                        script {
                            env.MERKLE_SERVICE_ENDPOINT = sh(script: "kubectl get svc ${RELEASE_NAME}-merkleservice -n ${NAMESPACE}-${APP_NAME} -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}'", returnStdout: true).trim()
                        }
                    }
                }
                failure {
                    container('kubectl') {
                        script {
                            sh """
                                echo "Deployment failed, collecting debug information..."
                                
                                echo "\\nHelm Status:"
                                helm list -n ${NAMESPACE}-${APP_NAME} || true
                                helm history zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME} -n ${NAMESPACE}-${APP_NAME} || true
                                
                                echo "\\nPod Status:"
                                kubectl get pods -n ${NAMESPACE}-${APP_NAME} || true
                                
                                echo "\\nPod Details:"
                                kubectl describe pods -n ${NAMESPACE}-${APP_NAME} || true
                                
                                echo "\\nEvents:"
                                kubectl get events -n ${NAMESPACE}-${APP_NAME} || true
                            """
                        }
                    }
                }
            }
        }

        stage('Checkout') {
            steps {
                cleanWs()
                git url: '${GIT_URL}',
                    branch: 'main'
            }
        }

        stage('Build Image') {
            steps {
                container('docker') {
                    sh '''
                        # 创建 Dockerfile
                        cat <<EOF > Dockerfile
FROM rustlang/rust:nightly-bullseye as rust-builder

# 安装 Rust 构建依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    binaryen \
    && rm -rf /var/lib/apt/lists/*

# 安装 wasm-pack
RUN cargo install wasm-pack --locked

# 设置工作目录
WORKDIR /build
COPY . .

# 构建 Rust WASM
RUN wasm-pack build --release --out-name application --out-dir pkg && \
    wasm-opt -Oz -o ts/node_modules/zkwasm-ts-server/src/application/application_bg.wasm pkg/application_bg.wasm && \
    cp pkg/application_bg.wasm.d.ts ts/node_modules/zkwasm-ts-server/src/application/

# Node.js 构建阶段
FROM node:18 as node-builder

WORKDIR /build
COPY --from=rust-builder /build .

# 安装 TypeScript 和其他依赖
RUN npm install -g typescript && \
    cd ts && \
    npm ci --verbose && \
    npx tsc

# 最终运行阶段
FROM node:18-slim

WORKDIR /app

# 只复制需要的文件
COPY --from=node-builder /build/ts /app

# 设置环境变量
ENV URI \
    REDISHOST \
    MERKLE_SERVER

EXPOSE 3000
CMD ["node", "src/service.js"]
EOF

                        # 只构建本地镜像
                        docker build -t ${FULL_IMAGE_NAME} .
                        
                        # 保存镜像为 tar 文件（可选）
                        docker save ${FULL_IMAGE_NAME} > ${IMAGE_NAME}-${IMAGE_TAG}.tar
                    '''
                }
            }
        }

        stage('Deploy') {
            steps {
                container('kubectl') {
                    sh '''
                        # 检查命名空间是否存在
                        if ! kubectl get namespace ${NAMESPACE}-${APP_NAME} >/dev/null 2>&1; then
                            echo "Creating namespace ${NAMESPACE}-${APP_NAME}..."
                            kubectl create namespace ${NAMESPACE}-${APP_NAME}
                        fi

                        echo "Creating deployment in namespace ${NAMESPACE}-${APP_NAME}..."
                        
                        # 创建部署配置
                        cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zkwasm-app-${CUSTOMER_ID}-${APP_NAME}
  namespace: ${NAMESPACE}-${APP_NAME}
  labels:
    app: zkwasm-app-${CUSTOMER_ID}-${APP_NAME}
    version: ${IMAGE_TAG}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zkwasm-app-${CUSTOMER_ID}-${APP_NAME}
  template:
    metadata:
      labels:
        app: zkwasm-app-${CUSTOMER_ID}-${APP_NAME}
    spec:
      containers:
      - name: app
        image: ${FULL_IMAGE_NAME}
        imagePullPolicy: Never  # 使用本地镜像
        env:
        - name: URI
          value: "mongodb://${RELEASE_NAME}-mongodb:27017"
        - name: REDISHOST
          value: "${RELEASE_NAME}-redis"
        - name: MERKLE_SERVER
          value: "http://${RELEASE_NAME}-merkleservice:3030"
        ports:
        - containerPort: 3000
          name: http
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
EOF

                        echo "Waiting for deployment to be ready..."
                        kubectl rollout status deployment/zkwasm-app-${CUSTOMER_ID}-${APP_NAME} \
                            -n ${NAMESPACE}-${APP_NAME} --timeout=5m
                    '''
                }
            }
            post {
                failure {
                    container('kubectl') {
                        sh '''
                            echo "Deployment failed. Collecting debug information..."
                            
                            echo "\\nPod Status:"
                            kubectl get pods -n ${NAMESPACE}-${APP_NAME} -l app=zkwasm-app-${CUSTOMER_ID}-${APP_NAME}
                            
                            echo "\\nPod Details:"
                            kubectl describe pods -n ${NAMESPACE}-${APP_NAME} -l app=zkwasm-app-${CUSTOMER_ID}-${APP_NAME}
                            
                            echo "\\nPod Logs:"
                            for pod in $(kubectl get pods -n ${NAMESPACE}-${APP_NAME} -l app=zkwasm-app-${CUSTOMER_ID}-${APP_NAME} -o name); do
                                echo "\\nLogs for $pod:"
                                kubectl logs $pod -n ${NAMESPACE}-${APP_NAME} --all-containers || true
                            done
                            
                            echo "\\nEvents:"
                            kubectl get events -n ${NAMESPACE}-${APP_NAME} --sort-by=.metadata.creationTimestamp
                        '''
                    }
                }
            }
        }

    }
}