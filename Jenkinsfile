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
                  - name: rust
                    image: rustlang/rust:nightly-bullseye
                    imagePullPolicy: IfNotPresent
                    command:
                    - cat
                    tty: true
                    volumeMounts:
                    - name: build-cache
                      mountPath: /shared-cache
                      subPath: cargo
                  - name: node
                    image: node:18
                    imagePullPolicy: IfNotPresent
                    command:
                    - cat
                    tty: true
                    volumeMounts:
                    - name: build-cache
                      mountPath: /root/.npm
                      subPath: npm
                  - name: kubectl
                    image: alpine/k8s:1.24.13
                    imagePullPolicy: IfNotPresent
                    command:
                    - cat
                    tty: true
                  volumes:
                  - name: build-cache
                    persistentVolumeClaim:
                      claimName: shared-build-cache
            '''
            defaultContainer 'rust'
        }
    }

    environment {
        DOCKER_REGISTRY = "${env.DOCKER_REGISTRY}"
        CARGO_HOME = "/usr/local/cargo"
        RUSTUP_HOME = "/usr/local/rustup"
        IMAGE_NAME = 'zkwasm-server'
        IMAGE_TAG = "${BUILD_NUMBER}"
        CUSTOMER_ID = "${params.CUSTOMER_ID}"
        NAMESPACE = "zkwasm-${CUSTOMER_ID}"
        FULL_IMAGE_NAME = "${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        GIT_URL = "${params.GIT_URL}"
        APP_NAME = "${params.APP_NAME}"
        MINIROLLUP_CHARTS_REPO = "${params.MINIROLLUP_CHARTS_REPO}"
        RELEASE_NAME = "zkwasm-mini-rollup-${CUSTOMER_ID}-${APP_NAME}"
    }

    stages {
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

        stage('Parallel Setup') {
            parallel {
                stage('Setup Rust Environment') {
                    steps {
                        sh '''
                            # 删除 rust-toolchain 文件
                            rm -f rust-toolchain
                            
                            # 设置 Rust 环境变量
                            export RUSTUP_HOME=/usr/local/rustup
                            export CARGO_HOME=/usr/local/cargo
                            export PATH="/usr/local/cargo/bin:$PATH"
                            
                            # 创建并导出环境变量
                            mkdir -p ${CARGO_HOME}
                            echo 'export PATH="$CARGO_HOME/bin:$PATH"' > ${CARGO_HOME}/env
                            chmod +x ${CARGO_HOME}/env
                            . ${CARGO_HOME}/env
                            
                            # 检查 Rust 环境
                            echo "Checking Rust environment..."
                            echo "PATH=$PATH"
                            echo "RUSTUP_HOME=$RUSTUP_HOME"
                            echo "CARGO_HOME=$CARGO_HOME"
                            
                            # 检查必要工具是否已安装
                            NEED_TOOLS=false
                            
                            # 检查基础工具
                            for tool in binaryen; do
                                if ! dpkg -l | grep -q "^ii  $tool "; then
                                    echo "$tool needs to be installed"
                                    NEED_TOOLS=true
                                    break
                                fi
                            done
                            
                            # 如果需要安装基础工具
                            if [ "$NEED_TOOLS" = true ]; then
                                echo "Installing basic tools..."
                                apt-get update && apt-get install -y --no-install-recommends \
                                    binaryen \
                                    && rm -rf /var/lib/apt/lists/*
                            else
                                echo "Basic tools already installed, skipping..."
                            fi
                            
                            # 检查 wasm-pack
                            if ! command -v wasm-pack >/dev/null; then
                                echo "Installing wasm-pack..."
                                # 使用系统自带的 cargo 直接安装
                                /usr/local/cargo/bin/cargo install wasm-pack --locked
                            else
                                echo "wasm-pack already installed, checking version..."
                                wasm-pack --version
                            fi
                            
                            # 验证工具链
                            echo "Verifying toolchain..."
                            rustc --version
                            cargo --version
                            wasm-opt --version
                            rustup target list | grep wasm32
                        '''
                    }
                }
                
                stage('Setup Node Environment') {
                    steps {
                        container('node') {
                            sh '''
                                # 预安装全局依赖
                                npm install -g typescript
                        
                                if [ -f "package.json" ]; then
                                    npm ci --verbose
                                fi
                            '''
                        }
                    }
                }
            }
        }

        stage('Parallel Build') {
            parallel {
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

        stage('Test Run') {
            steps {
                container('kubectl') {
                    sh '''
                        # 获取 merkle service IP
                        MERKLE_SVC_IP=$(kubectl get svc -n ${NAMESPACE}-${APP_NAME} ${RELEASE_NAME}-merkleservice -o jsonpath='{.spec.clusterIP}')
                        echo "Merkle service IP: $MERKLE_SVC_IP"
                        echo "$MERKLE_SVC_IP" > merkle_ip.txt
                    '''
                }
                
                container('node') {
                    sh '''
                        set -e
                        cd ts
                        
                        # 读取 merkle service IP
                        MERKLE_SVC_IP=$(cat ../merkle_ip.txt)
                        echo "Using Merkle service IP: $MERKLE_SVC_IP"
                        
                        # 等待 merkle service 就绪
                        echo "Waiting for merkle service to be ready..."
                        for i in $(seq 1 30); do
                            if curl -s http://$MERKLE_SVC_IP:3030/health > /dev/null 2>&1; then
                                echo "Merkle service is healthy"
                                break
                            fi
                            if [ $i -eq 30 ]; then
                                echo "Merkle service is not ready after 30 attempts"
                                exit 1
                            fi
                            echo "Waiting for merkle service... attempt $i/30"
                            sleep 2
                        done
                        
                        # 设置环境变量
                        export URI="mongodb://${RELEASE_NAME}-mongodb:27017"
                        export REDISHOST="${RELEASE_NAME}-redis"
                        export MERKLE_SERVER="http://$MERKLE_SVC_IP:3030"
                        
                        echo "Starting application with environment variables:"
                        echo "URI=$URI"
                        echo "REDISHOST=$REDISHOST"
                        echo "MERKLE_SERVER=$MERKLE_SERVER"
                        
                        # 后台运行应用
                        node src/service.js &
                        echo $! > .pid
                        
                        echo "Waiting for application to start..."
                        for i in $(seq 1 30); do
                            if curl -s http://localhost:3000/health > /dev/null; then
                                echo "Application is healthy"
                                exit 0
                            fi
                            sleep 1
                        done
                        echo "Application failed to start"
                        exit 1
                    '''
                }
            }
        }

        stage('Deploy') {
            steps {
                container('kubectl') {
                    sh '''
                        # Debug information
                        echo "Current directory: $(pwd)"
                        echo "WORKSPACE: ${WORKSPACE}"
                        echo "Directory contents:"
                        ls -la
                        echo "Parent directory contents:"
                        ls -la ..
                        
                        echo "Creating deployment in namespace ${NAMESPACE}-${APP_NAME}..."
                        
                        # 清理现有资源
                        echo "Cleaning up existing resources..."
                        kubectl delete deployment zkwasm-app-${CUSTOMER_ID}-${APP_NAME} -n ${NAMESPACE}-${APP_NAME} --ignore-not-found=true
                        kubectl delete pod workspace-copy -n ${NAMESPACE}-${APP_NAME} --ignore-not-found=true
                        
                        # 创建 ConfigMap 来存储文件
                        echo "Creating ConfigMap from ts directory..."
                        kubectl create configmap app-files -n ${NAMESPACE}-${APP_NAME} \
                            --from-file=./ts || true
                        
                        echo "Creating deployment..."
                        cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zkwasm-app-${CUSTOMER_ID}-${APP_NAME}
  namespace: ${NAMESPACE}-${APP_NAME}
  labels:
    app: zkwasm-app-${CUSTOMER_ID}-${APP_NAME}
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
      initContainers:
      - name: copy-files
        image: node:18-slim
        command: 
        - /bin/sh
        - -c
        - |
          echo "Copying files to app directory..."
          cp -rv /config/* /app/
          echo "App directory contents:"
          ls -la /app
        volumeMounts:
        - name: app-files
          mountPath: /app
        - name: config-volume
          mountPath: /config
      containers:
      - name: app
        image: node:18-slim
        command: ["node"]
        args: ["src/service.js"]
        workingDir: /app
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
        readinessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 15
          periodSeconds: 20
        volumeMounts:
        - name: app-files
          mountPath: /app
      volumes:
      - name: app-files
        emptyDir: {}
      - name: config-volume
        configMap:
          name: app-files
EOF

                        echo "Waiting for deployment to be ready..."
                        kubectl rollout status deployment/zkwasm-app-${CUSTOMER_ID}-${APP_NAME} \
                            -n ${NAMESPACE}-${APP_NAME} --timeout=5m || true
                        
                        echo "Final deployment status and logs:"
                        POD_NAME=$(kubectl get pods -n ${NAMESPACE}-${APP_NAME} -l app=zkwasm-app-${CUSTOMER_ID}-${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
                        echo "Pod status:"
                        kubectl get pod ${POD_NAME} -n ${NAMESPACE}-${APP_NAME}
                        echo "Init container logs:"
                        kubectl logs ${POD_NAME} -c copy-files -n ${NAMESPACE}-${APP_NAME} || true
                        echo "App container logs:"
                        kubectl logs ${POD_NAME} -c app -n ${NAMESPACE}-${APP_NAME} || true
                    '''
                }
            }
        }
    }
}