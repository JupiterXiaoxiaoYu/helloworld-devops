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
                  - name: buildah
                    image: quay.io/buildah/stable:latest
                    imagePullPolicy: IfNotPresent
                    securityContext:
                      privileged: true
                    command:
                    - cat
                    tty: true
                    env:
                    - name: BUILDAH_ISOLATION
                      value: chroot
                    volumeMounts:
                    - name: build-storage
                      mountPath: /var/lib/containers
                    - name: build-cache
                      mountPath: /cache
                  - name: kubectl
                    image: alpine/k8s:1.24.13
                    imagePullPolicy: IfNotPresent
                    command:
                    - cat
                    tty: true
                    volumeMounts:
                    - name: build-cache
                      mountPath: /cache
                  - name: ctr
                    image: rancher/k3s:v1.24.13-k3s1 
                    imagePullPolicy: IfNotPresent
                    command:
                    - cat
                    tty: true
                    securityContext:
                      privileged: true
                    env:
                    - name: CONTAINERD_ADDRESS
                      value: /run/containerd/containerd.sock
                    - name: CONTAINERD_NAMESPACE
                      value: k8s.io
                    volumeMounts:
                    - name: build-cache
                      mountPath: /cache
                    - name: host-containerd-sock
                      mountPath: /run/containerd/containerd.sock
                    - name: host-containerd-sock
                      mountPath: /run/k3s/containerd/containerd.sock
                  volumes:
                  - name: build-storage
                    emptyDir: {}
                  - name: build-cache
                    persistentVolumeClaim:
                      claimName: shared-build-cache
                  - name: host-containerd-sock
                    hostPath:
                      path: /run/containerd/containerd.sock
                      type: Socket
            '''
            defaultContainer 'kubectl'
        }
    }

    environment {
        IMAGE_NAME = 'zkwasm-server'
        IMAGE_TAG = "${BUILD_NUMBER}"
        CUSTOMER_ID = "${params.CUSTOMER_ID}"
        NAMESPACE = "zkwasm-${CUSTOMER_ID}"
        FULL_IMAGE_NAME = "${IMAGE_NAME}-${CUSTOMER_ID}-${APP_NAME}"
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


        stage('Build Image') {
            steps {
                container('buildah') {
                    sh '''
                        # 检查缓存目录是否存在已构建的镜像
                        ls -lh /cache/images/
                        if [ -f "/cache/images/${FULL_IMAGE_NAME}.tar" ]; then
                            echo "Found cached image: /cache/images/${FULL_IMAGE_NAME}.tar"
                            echo "Skipping build stage..."
                            exit 0
                        fi

                        echo "No cached image found, proceeding with build..."
                        # 创建 Containerfile (等同于 Dockerfile)
                        cat <<EOF > Containerfile
FROM docker.io/library/node:18 as node-builder

# Install git and configure npm for better network resilience
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/* \
    && npm config set fetch-retry-mintimeout 20000 \
    && npm config set fetch-retry-maxtimeout 120000 \
    && npm config set fetch-retries 5

# Set work directory and clone repository
WORKDIR /build
RUN git clone ${GIT_URL} .

# Install TypeScript and dependencies with retry mechanism
RUN npm install -g typescript || npm install -g typescript || npm install -g typescript && \
    cd ts && \
    rm -rf package-lock.json && \
    (npm i --verbose || (sleep 10 && npm i --verbose) || (sleep 30 && npm i --verbose))

# Rust 构建阶段
FROM docker.io/rustlang/rust:nightly-bullseye as rust-builder

# 安装 Rust 构建依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    binaryen \
    && rm -rf /var/lib/apt/lists/*

# 安装 wasm-pack
RUN cargo install wasm-pack --locked

# 设置工作目录并复制代码
WORKDIR /build
COPY --from=node-builder /build .

# 构建 Rust WASM
RUN wasm-pack build --release --out-name application --out-dir pkg && \
    wasm-opt -Oz -o ts/node_modules/zkwasm-ts-server/src/application/application_bg.wasm pkg/application_bg.wasm && \
    cp pkg/application_bg.wasm.d.ts ts/node_modules/zkwasm-ts-server/src/application/

# 回到 node-builder 完成 TypeScript 编译
FROM node-builder as ts-builder
COPY --from=rust-builder /build/pkg ./pkg
COPY --from=rust-builder /build/ts/node_modules/zkwasm-ts-server/src/application ./ts/node_modules/zkwasm-ts-server/src/application
RUN cd ts && npx tsc

# 最终运行阶段
FROM docker.io/library/node:18-slim

WORKDIR /app

# 只复制需要的文件
COPY --from=ts-builder /build/ts /app

# 设置环境变量
ENV URI="" \
    REDISHOST="" \
    MERKLE_SERVER=""

EXPOSE 3000
CMD ["node", "src/service.js"] 
EOF

                        # 使用 Buildah 构建镜像
                        buildah bud -t ${FULL_IMAGE_NAME} -f Containerfile .
                        
                        # 将镜像保存为 OCI 格式
                        mkdir -p /cache/images
                        echo "Saving image to: /cache/images/${FULL_IMAGE_NAME}.tar"
                
                        # 使用完整路径和.tar扩展名
                        buildah push ${FULL_IMAGE_NAME} docker-archive:/cache/images/${FULL_IMAGE_NAME}.tar
                        
                        # 验证文件
                        echo "Saved files:"
                        ls -lh /cache/images/
                    '''
                }
            }
        }

        stage('Deploy') {
            steps {
                container('ctr') {
                    sh '''
                        # 设置本地镜像名称
                        LOCAL_IMAGE="localhost/${FULL_IMAGE_NAME}"
                        
                        echo "Importing image to containerd..."
                        ctr -n=k8s.io images import --base-name ${LOCAL_IMAGE} "/cache/images/${FULL_IMAGE_NAME}.tar"
                        
                        echo "Verifying image in containerd..."
                        ctr -n=k8s.io images ls | grep ${LOCAL_IMAGE}
                        
                        # 获取 MongoDB 服务地址
                        MONGODB_SERVICE="${RELEASE_NAME}-mongodb.${NAMESPACE}-${APP_NAME}.svc.cluster.local"
                        
                        # 检查并删除现有的部署
                        echo "Checking for existing deployment..."
                        if kubectl get deployment -n ${NAMESPACE}-${APP_NAME} zkwasm-app-${CUSTOMER_ID}-${APP_NAME} >/dev/null 2>&1; then
                            echo "Found existing deployment, deleting it..."
                            kubectl delete deployment -n ${NAMESPACE}-${APP_NAME} zkwasm-app-${CUSTOMER_ID}-${APP_NAME} --timeout=60s
                            
                            # 等待旧的 pods 完全终止
                            echo "Waiting for old pods to terminate..."
                            kubectl wait --for=delete pod -l app=zkwasm-app-${CUSTOMER_ID}-${APP_NAME} -n ${NAMESPACE}-${APP_NAME} --timeout=60s || true
                        fi
                        
                        echo "Creating new deployment..."
                        cat <<EOF | kubectl apply -f -
                        apiVersion: apps/v1
                        kind: Deployment
                        metadata:
                          name: zkwasm-app-${CUSTOMER_ID}-${APP_NAME}
                          namespace: ${NAMESPACE}-${APP_NAME}
                          labels:
                            app: "zkwasm-app-${CUSTOMER_ID}-${APP_NAME}"
                        spec:
                          replicas: 1
                          selector:
                            matchLabels:
                              app: "zkwasm-app-${CUSTOMER_ID}-${APP_NAME}"
                          template:
                            metadata:
                              labels:
                                app: "zkwasm-app-${CUSTOMER_ID}-${APP_NAME}"
                            spec:
                              containers:
                              - name: app
                                image: ${LOCAL_IMAGE}:latest
                                imagePullPolicy: Never
                                env:
                                - name: NODE_ENV
                                  value: "production"
                                - name: URI
                                  value: "mongodb://${MONGODB_SERVICE}:27017"
                                - name: REDISHOST
                                  value: "${RELEASE_NAME}-redis.${NAMESPACE}-${APP_NAME}.svc.cluster.local"
                                - name: MERKLE_SERVER
                                  value: "http://${RELEASE_NAME}-merkleservice.${NAMESPACE}-${APP_NAME}.svc.cluster.local:3030"
EOF

                        echo "Waiting for new pod to be ready..."
                        kubectl -n ${NAMESPACE}-${APP_NAME} wait --for=condition=ready pod -l app=zkwasm-app-${CUSTOMER_ID}-${APP_NAME} --timeout=300s
                        
                        echo "Deployment completed successfully"
                    '''
                }
            }
            post {
                failure {
                    container('kubectl') {
                        sh '''
                            echo "Deployment failed. Collecting debug information..."
                            
                            echo "\\nContainerd images:"
                            ctr -n=k8s.io images ls || true
                            
                            echo "\\nPod status:"
                            kubectl get pods -n ${NAMESPACE}-${APP_NAME} -o wide || true
                            
                            echo "\\nPod description:"
                            kubectl describe pod -n ${NAMESPACE}-${APP_NAME} -l app=zkwasm-app-${CUSTOMER_ID}-${APP_NAME} || true
                            
                            echo "\\nNode status:"
                            kubectl describe node $(hostname) || true
                        '''
                    }
                }
            }
        }

    }
}