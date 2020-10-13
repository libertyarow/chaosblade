.PHONY: build clean

export BLADE_VERSION=0.7.0

ALLOWGITVERSION=1.8.5
GITVERSION:=$(shell git --version | grep ^git | sed 's/^.* //g')

ifneq ($(strip $(firstword $(sort $(GITVERSION), $(ALLOWGITVERSION)))),$(ALLOWGITVERSION))
	ALERTMSG="please update git to >= $(ALLOWGITVERSION)"
endif

BLADE_BIN=blade
BLADE_EXPORT=chaosblade-$(BLADE_VERSION).tgz
BLADE_SRC_ROOT=$(shell pwd)

GO_ENV=CGO_ENABLED=1
GO_MODULE=GO111MODULE=on
VERSION_PKG=github.com/chaosblade-io/chaosblade/version
# Specify chaosblade version in docker experiments
DOCKER_BLADE_VERSION=github.com/chaosblade-io/chaosblade-exec-docker/version
OS_BLADE_VERSION=github.com/chaosblade-io/chaosblade-exec-os/version

GO_X_FLAGS=-X ${VERSION_PKG}.Ver=$(BLADE_VERSION) -X '${VERSION_PKG}.Env=`uname -mv`' -X '${VERSION_PKG}.BuildTime=`date`' -X ${DOCKER_BLADE_VERSION}.BladeVersion=$(BLADE_VERSION) -X ${OS_BLADE_VERSION}.BladeVersion=$(BLADE_VERSION)
GO_FLAGS=-ldflags="$(GO_X_FLAGS) -s -w"
GO=env $(GO_ENV) $(GO_MODULE) go

UNAME := $(shell uname)

BUILD_TARGET=target
BUILD_TARGET_FOR_JAVA_CPLUS=build-target
BUILD_TARGET_DIR_NAME=chaosblade-$(BLADE_VERSION)
BUILD_TARGET_PKG_DIR=$(BUILD_TARGET)/chaosblade-$(BLADE_VERSION)
BUILD_TARGET_PKG_NAME=$(BUILD_TARGET)/chaosblade-$(BLADE_VERSION).tar.gz
BUILD_TARGET_BIN=$(BUILD_TARGET_PKG_DIR)/bin
BUILD_TARGET_LIB=$(BUILD_TARGET_PKG_DIR)/lib
BUILD_TARGET_YAML=$(BUILD_TARGET_PKG_DIR)/yaml
BUILD_TARGET_TAR_NAME=$(BUILD_TARGET_DIR_NAME).tar.gz
BUILD_TARGET_PKG_FILE_PATH=$(BUILD_TARGET)/$(BUILD_TARGET_TAR_NAME)
BUILD_IMAGE_PATH=build/image/blade
# cache downloaded file
BUILD_TARGET_CACHE=$(BUILD_TARGET)/cache

# chaosblade-exec-os
BLADE_EXEC_OS_PROJECT=https://github.com/chaosblade-io/chaosblade-exec-os.git
BLADE_EXEC_OS_BRANCH=master

# chaosblade-exec-docker
BLADE_EXEC_DOCKER_PROJECT=https://github.com/chaosblade-io/chaosblade-exec-docker.git
BLADE_EXEC_DOCKER_BRANCH=master

# chaosblade-exec-kubernetes
BLADE_OPERATOR_PROJECT=https://github.com/chaosblade-io/chaosblade-operator.git
BLADE_OPERATOR_BRANCH=master

# chaosblade-exec-jvm
BLADE_EXEC_JVM_PROJECT=https://github.com/chaosblade-io/chaosblade-exec-jvm.git
BLADE_EXEC_JVM_BRANCH=master

# chaosblade-exec-cplus
BLADE_EXEC_CPLUS_PROJECT=https://github.com/chaosblade-io/chaosblade-exec-cplus.git
BLADE_EXEC_CPLUS_BRANCH=master

# docker yaml
DOCKER_YAML_FILE_NAME=chaosblade-docker-spec-$(BLADE_VERSION).yaml
DOCKER_YAML_FILE_PATH=$(BUILD_TARGET_BIN)/$(DOCKER_YAML_FILE_NAME)

ifeq ($(GOOS), linux)
	GO_FLAGS=-ldflags="-linkmode external -extldflags -static $(GO_X_FLAGS) -s -w"
endif

help:
	@echo ''
	@echo 'You can compile each project of ChaosBlade on Mac or Linux platform, and on Mac platform, '
	@echo 'You can use docker to compile cross-platform,compile the package running on Linux platform.'
	@echo 'For details refer to https://github.com/chaosblade-io/chaosblade/wiki/ChaosBlade-Projects-Compilation'
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>...\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-16s\033[0m  %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build
build: pre_build build_cli build_os build_docker build_kubernetes build_cplus build_java upx package  ## Build all scenarios

# for example: make build_with cli os_darwin
build_with: pre_build ## Select scenario build, for example `make build_with cli os docker kubernetes java cplus`

# for example: make build_with_linux cli os
build_with_linux: pre_build build_linux_with_arg ## Select scenario build linux version by docker image, for example `make build_with_linux ARGS="cli os"`

# build chaosblade linux version by docker image
build_linux: pre_build ## Build linux version of all scenarios by docker image
	docker build -f build/image/musl/Dockerfile -t chaosblade-build-musl:latest build/image/musl
	docker run --rm \
		-v $(shell echo -n ${GOPATH}):/go \
		-w /go/src/github.com/chaosblade-io/chaosblade \
		-v ~/.m2/repository:/root/.m2/repository \
		-v $(shell pwd):/go/src/github.com/chaosblade-io/chaosblade \
		chaosblade-build-musl:latest build

build_darwin: pre_build build_cli build_os_darwin build_docker build_kubernetes build_java build_cplus upx package ## Build all scenarios darwin version

##@ Build sub

# create dir or download necessary file
pre_build: mkdir_build_target ## Mkdir build target
	rm -rf $(BUILD_TARGET_PKG_DIR) $(BUILD_TARGET_PKG_FILE_PATH)
	mkdir -p $(BUILD_TARGET_BIN) $(BUILD_TARGET_LIB) $(BUILD_TARGET_YAML)

# build chaosblade cli: blade
build_cli: ## Build blade cli
	$(GO) build $(GO_FLAGS) -o $(BUILD_TARGET_PKG_DIR)/blade ./cli

build_os: ## Build basic resource experimental scenarios.
ifneq ($(BUILD_TARGET_CACHE)/chaosblade-exec-os, $(wildcard $(BUILD_TARGET_CACHE)/chaosblade-exec-os))
	git clone -b $(BLADE_EXEC_OS_BRANCH) $(BLADE_EXEC_OS_PROJECT) $(BUILD_TARGET_CACHE)/chaosblade-exec-os
else
ifdef ALERTMSG
	$(error $(ALERTMSG))
endif
	git -C $(BUILD_TARGET_CACHE)/chaosblade-exec-os pull origin $(BLADE_EXEC_OS_BRANCH)
endif
	make -C $(BUILD_TARGET_CACHE)/chaosblade-exec-os
	cp $(BUILD_TARGET_CACHE)/chaosblade-exec-os/$(BUILD_TARGET_BIN)/* $(BUILD_TARGET_BIN)
	cp $(BUILD_TARGET_CACHE)/chaosblade-exec-os/$(BUILD_TARGET_YAML)/* $(BUILD_TARGET_YAML)

build_os_darwin: ## Build basic resource experimental scenarios for darwin.
ifneq ($(BUILD_TARGET_CACHE)/chaosblade-exec-os, $(wildcard $(BUILD_TARGET_CACHE)/chaosblade-exec-os))
	git clone -b $(BLADE_EXEC_OS_BRANCH) $(BLADE_EXEC_OS_PROJECT) $(BUILD_TARGET_CACHE)/chaosblade-exec-os
else
ifdef ALERTMSG
	$(error $(ALERTMSG))
endif
	git -C $(BUILD_TARGET_CACHE)/chaosblade-exec-os pull origin $(BLADE_EXEC_OS_BRANCH)
endif
	make build_darwin -C $(BUILD_TARGET_CACHE)/chaosblade-exec-os
	cp $(BUILD_TARGET_CACHE)/chaosblade-exec-os/$(BUILD_TARGET_BIN)/* $(BUILD_TARGET_BIN)
	cp $(BUILD_TARGET_CACHE)/chaosblade-exec-os/$(BUILD_TARGET_YAML)/* $(BUILD_TARGET_YAML)

build_docker: ## Build docker experimental scenarios.
ifneq ($(BUILD_TARGET_CACHE)/chaosblade-exec-docker, $(wildcard $(BUILD_TARGET_CACHE)/chaosblade-exec-docker))
	git clone -b $(BLADE_EXEC_DOCKER_BRANCH) $(BLADE_EXEC_DOCKER_PROJECT) $(BUILD_TARGET_CACHE)/chaosblade-exec-docker
else
	git -C $(BUILD_TARGET_CACHE)/chaosblade-exec-docker pull origin $(BLADE_EXEC_DOCKER_BRANCH)
endif
	make -C $(BUILD_TARGET_CACHE)/chaosblade-exec-docker
	cp $(BUILD_TARGET_CACHE)/chaosblade-exec-docker/$(BUILD_TARGET_YAML)/* $(BUILD_TARGET_YAML)

build_kubernetes: ## Build kubernetes experimental scenarios.
ifneq ($(BUILD_TARGET_CACHE)/chaosblade-operator, $(wildcard $(BUILD_TARGET_CACHE)/chaosblade-operator))
	git clone -b $(BLADE_OPERATOR_BRANCH) $(BLADE_OPERATOR_PROJECT) $(BUILD_TARGET_CACHE)/chaosblade-operator
else
	git -C $(BUILD_TARGET_CACHE)/chaosblade-operator pull origin $(BLADE_OPERATOR_BRANCH)
endif
	make -C $(BUILD_TARGET_CACHE)/chaosblade-operator
	cp $(BUILD_TARGET_CACHE)/chaosblade-operator/$(BUILD_TARGET_BIN)/* $(BUILD_TARGET_BIN)
	cp $(BUILD_TARGET_CACHE)/chaosblade-operator/$(BUILD_TARGET_YAML)/* $(BUILD_TARGET_YAML)

build_java: ## Build java experimental scenarios.
ifneq ($(BUILD_TARGET_CACHE)/chaosblade-exec-jvm, $(wildcard $(BUILD_TARGET_CACHE)/chaosblade-exec-jvm))
	git clone -b $(BLADE_EXEC_JVM_BRANCH) $(BLADE_EXEC_JVM_PROJECT) $(BUILD_TARGET_CACHE)/chaosblade-exec-jvm
else
ifdef ALERTMSG
	$(error $(ALERTMSG))
endif
	git -C $(BUILD_TARGET_CACHE)/chaosblade-exec-jvm pull origin $(BLADE_EXEC_JVM_BRANCH)
endif
	make -C $(BUILD_TARGET_CACHE)/chaosblade-exec-jvm
	cp -R $(BUILD_TARGET_CACHE)/chaosblade-exec-jvm/$(BUILD_TARGET_FOR_JAVA_CPLUS)/$(BUILD_TARGET_DIR_NAME)/* $(BUILD_TARGET_PKG_DIR)

build_cplus: ## Build c/c++ experimental scenarios.
ifneq ($(BUILD_TARGET_CACHE)/chaosblade-exec-cplus, $(wildcard $(BUILD_TARGET_CACHE)/chaosblade-exec-cplus))
	git clone -b $(BLADE_EXEC_CPLUS_BRANCH) $(BLADE_EXEC_CPLUS_PROJECT) $(BUILD_TARGET_CACHE)/chaosblade-exec-cplus
else
ifdef ALERTMSG
	$(error $(ALERTMSG))
endif
	git -C $(BUILD_TARGET_CACHE)/chaosblade-exec-cplus pull origin $(BLADE_EXEC_CPLUS_BRANCH)
endif
	make -C $(BUILD_TARGET_CACHE)/chaosblade-exec-cplus
	cp -R $(BUILD_TARGET_CACHE)/chaosblade-exec-cplus/$(BUILD_TARGET_FOR_JAVA_CPLUS)/$(BUILD_TARGET_DIR_NAME)/* $(BUILD_TARGET_PKG_DIR)

##@ Build image
# build chaosblade image for chaos
build_image: ## Build chaosblade-tool image
	rm -rf $(BUILD_IMAGE_PATH)/$(BUILD_TARGET_DIR_NAME)
	cp -R $(BUILD_TARGET_PKG_NAME) $(BUILD_IMAGE_PATH)
	tar zxvf $(BUILD_TARGET_PKG_NAME) -C $(BUILD_IMAGE_PATH)
	docker build -f $(BUILD_IMAGE_PATH)/Dockerfile \
		--build-arg BLADE_VERSION=$(BLADE_VERSION) \
		-t chaosblade-tool:$(BLADE_VERSION) \
		$(BUILD_IMAGE_PATH)
	rm -rf $(BUILD_IMAGE_PATH)/$(BUILD_TARGET_DIR_NAME)

# build docker image with multi-stage builds
docker_image: clean ## Build chaosblade image
	docker build -f ./Dockerfile \
		--build-arg BLADE_VERSION=$(BLADE_VERSION) \
		-t chaosblade:$(BLADE_VERSION) $(BLADE_SRC_ROOT)

build_upx_image: ## Build chaosblade-upx image
	docker build --rm \
 		-f build/image/upx/Dockerfile \
 		-t chaosblade-upx:3.96 build/image/upx

##@ Other
upx: ## Upx compression by docker image
ifeq ($(shell docker images -q chaosblade-upx:3.96),)
	make build_upx_image
endif
	docker run --rm \
    		-w $(shell pwd)/$(BUILD_TARGET_PKG_DIR) \
    		-v $(shell pwd)/$(BUILD_TARGET_PKG_DIR):$(shell pwd)/$(BUILD_TARGET_PKG_DIR) \
     		chaosblade-upx:3.96 \
    		--best \
    		blade $(shell pwd)/$(BUILD_TARGET_PKG_DIR)/bin/*

test: ## Test
	$(GO) test -race -coverprofile=coverage.txt -covermode=atomic ./...

# clean all build result
clean: ## Clean
	$(GO) clean ./...
	rm -rf $(BUILD_TARGET)
	rm -rf $(BUILD_IMAGE_PATH)/$(BUILD_TARGET_DIR_NAME)

package: ## Generate the tar packages
	tar zcvf $(BUILD_TARGET_PKG_FILE_PATH) -C $(BUILD_TARGET) $(BUILD_TARGET_DIR_NAME)

# alias
cli: build_cli
os: build_os
os_darwin: build_os_darwin
docker: build_docker
kubernetes: build_kubernetes
java: build_java
cplus: build_cplus

## Select scenario build linux version by docker image
build_linux_with_arg:
	docker build -f build/image/musl/Dockerfile -t chaosblade-build-musl:latest build/image/musl
	docker run --rm \
		-v $(shell echo -n ${GOPATH}):/go \
		-w /go/src/github.com/chaosblade-io/chaosblade \
		-v ~/.m2/repository:/root/.m2/repository \
		-v $(shell pwd):/go/src/github.com/chaosblade-io/chaosblade \
		chaosblade-build-musl:latest build_with $$ARGS

# create cache dir
mkdir_build_target:
ifneq ($(BUILD_TARGET_CACHE), $(wildcard $(BUILD_TARGET_CACHE)))
	mkdir -p $(BUILD_TARGET_CACHE)
endif
