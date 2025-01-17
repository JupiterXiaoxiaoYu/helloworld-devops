INSTALL_DIR=./ts/node_modules/zkwasm-ts-server/src/application
RUNNING_DIR=./ts/node_modules/zkwasm-ts-server

default: build

./src/admin.pubkey: ./ts/node_modules/zkwasm-ts-server/src/init_admin.js
	node ./ts/node_modules/zkwasm-ts-server/src/init_admin.js ./src/admin.pubkey

./ts/src/service.js:
	cd ./ts && npx tsc && cd -

build: ./src/admin.pubkey ./ts/src/service.js
	wasm-pack build --release --out-name application --out-dir pkg
	wasm-opt -Oz -o $(INSTALL_DIR)/application_bg.wasm pkg/application_bg.wasm
	cp pkg/application_bg.wasm $(INSTALL_DIR)/application_bg.wasm
	#cp pkg/application.d.ts $(INSTALL_DIR)/application.d.ts
	#cp pkg/application_bg.js $(INSTALL_DIR)/application_bg.js
	cp pkg/application_bg.wasm.d.ts $(INSTALL_DIR)/application_bg.wasm.d.ts
	cd $(RUNNING_DIR) && npx tsc && cd -

clean:
	rm -rf pkg
	rm -rf ./src/admin.pubkey

run:
	node ./ts/src/service.js

deploy:
	docker build --file ./deploy/service.docker -t zkwasm-server . --network=host


# 定义路径变量
# CARGO_HOME=/home/devbox/.cargo
# CARGO_BIN=$(CARGO_HOME)/bin
# RUSTUP=$(CARGO_BIN)/rustup
# RUSTC=$(CARGO_BIN)/rustc
# CARGO=$(CARGO_BIN)/cargo
# WASM_PACK=$(CARGO_BIN)/wasm-pack
# WASM_OPT=$(CARGO_BIN)/wasm-opt
# INSTALL_DIR=./ts/node_modules/zkwasm-ts-server/src/application
# RUNNING_DIR=./ts/node_modules/zkwasm-ts-server

# default: build

# ./src/admin.pubkey: ./ts/node_modules/zkwasm-ts-server/src/init_admin.js
# 	node ./ts/node_modules/zkwasm-ts-server/src/init_admin.js ./src/admin.pubkey

# ./ts/src/service.js:
# 	cd ./ts && npx tsc && cd -

# build:
# 	@echo "Current directory: $$(pwd)"
# 	@if [ ! -f "Cargo.toml" ]; then \
# 		echo "Error: Cargo.toml not found in current directory"; \
# 		echo "Directory contents:"; \
# 		ls -la; \
# 		exit 1; \
# 	fi
# 	@echo "Found Cargo.toml, contents:"
# 	@cat Cargo.toml
# 	@echo "Building with wasm-pack..."
# 	. "$(CARGO_HOME)/env" && \
# 	sudo -u devbox \
# 		RUSTUP_HOME="/home/devbox/.rustup" \
# 		CARGO_HOME="$(CARGO_HOME)" \
# 		PATH="$(CARGO_BIN):$$PATH" \
# 		CARGO="$(CARGO)" \
# 		$(WASM_PACK) build --release --out-name application --out-dir pkg
# 	sudo -u devbox $(WASM_OPT) -Oz -o $(INSTALL_DIR)/application_bg.wasm pkg/application_bg.wasm
# 	sudo -u devbox cp pkg/application_bg.wasm $(INSTALL_DIR)/application_bg.wasm
# 	sudo -u devbox cp pkg/application_bg.wasm.d.ts $(INSTALL_DIR)/application_bg.wasm.d.ts
# 	cd $(RUNNING_DIR) && npx tsc && cd -

# clean:
# 	rm -rf pkg
# 	rm -rf ./src/admin.pubkey

# run:
# 	# @if [ -z "$$(docker ps -q -f name=zkwasm-mini-rollup)" ]; then \
# 	# 	echo "zkwasm-mini-rollup container is not running. Starting it..."; \
# 	# 	cd zkwasm-mini-rollup && docker-compose up -d; \
# 	# 	echo "Waiting for container to be ready..."; \
# 	# 	sleep 10; \
# 	# else \
# 	# 	echo "zkwasm-mini-rollup container is already running"; \
# 	# fi
# 	node ./ts/src/service.js

# setup:
# 	echo "Loading Rust environment..."
# 	sudo service docker start || true
# 	sudo -u devbox \
# 		RUSTUP_HOME="/home/devbox/.rustup" \
# 		CARGO_HOME="$(CARGO_HOME)" \
# 		PATH="$(CARGO_BIN):$$PATH" \
# 		$(RUSTUP) install nightly-2023-06-01 && \
# 	sudo -u devbox \
# 		RUSTUP_HOME="/home/devbox/.rustup" \
# 		CARGO_HOME="$(CARGO_HOME)" \
# 		PATH="$(CARGO_BIN):$$PATH" \
# 		$(RUSTUP) default nightly-2023-06-01 && \
# 	sudo -u devbox \
# 		RUSTUP_HOME="/home/devbox/.rustup" \
# 		CARGO_HOME="$(CARGO_HOME)" \
# 		PATH="$(CARGO_BIN):$$PATH" \
# 		$(RUSTUP) target add wasm32-unknown-unknown
# 	echo "Installing Node.js and npm..."
# 	if ! command -v node > /dev/null; then \
# 		curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && \
# 		sudo apt-get install -y nodejs; \
# 	fi
# 	echo "Installing Docker and Docker Compose..."
# 	if ! command -v docker > /dev/null; then \
# 		curl -fsSL https://get.docker.com | sudo sh && \
# 		sudo usermod -aG docker $$USER; \
# 	fi
# 	if ! command -v docker-compose > /dev/null; then \
# 		sudo apt-get update && \
# 		sudo apt-get install -y docker-compose; \
# 	fi
# 	echo "Installing wasm-pack..."
# 	if ! command -v wasm-pack > /dev/null; then \
# 		sudo -u devbox $(RUSTC) -vV && \
# 		sudo -u devbox $(CARGO) install wasm-pack; \
# 	fi
# 	echo "Installing wasm-opt (binaryen)..."
# 	if ! command -v wasm-opt > /dev/null; then \
# 		sudo -u devbox $(RUSTC) -vV && \
# 		sudo -u devbox $(CARGO) install wasm-opt; \
# 	fi
# 	# if [ -d "zkwasm-mini-rollup" ]; then \
# 	# 	echo "zkwasm-mini-rollup directory already exists"; \
# 	# else \
# 	# 	git clone https://github.com/DelphinusLab/zkwasm-mini-rollup.git && \
# 	# 	echo "Starting zkwasm-mini-rollup docker containers..." && \
# 	# 	(cd zkwasm-mini-rollup && docker-compose up -d); \
# 	# fi
# 	echo "Installing TypeScript dependencies..."
# 	(cd ts && \
# 	npm install && \
# 	npx tsc && \
# 	cd ..)
# 	echo "TypeScript setup completed"

# deploy:
# 	docker build --file ./deploy/service.docker -t zkwasm-server . --network=host
