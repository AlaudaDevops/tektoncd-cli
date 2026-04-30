###################################################
### WARNING: This file is synced from AlaudaDevops/tektoncd-operator
### DO NOT CHANGE IT MANUALLY
###################################################
TOOLBIN ?= $(shell pwd)/bin

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# SUFFIX is the suffix of the version, usually it is the short commit hash
SUFFIX ?=
# If SUFFIX is not empty and does not contain a dash, add a dash prefix
SUFFIX := $(if $(and $(SUFFIX),$(filter-out -%, $(SUFFIX))),-$(SUFFIX),$(SUFFIX))
# NEW_COMPONENT_VERSION is the new version of the component
NEW_COMPONENT_VERSION ?= $(VERSION)$(SUFFIX)

ARCH ?= amd64
GITNAME = $(shell git config --get user.name | sed 's/ //g')

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all-default
all-default: help-default

HELP_FUN = \
	%help; while(<>){push@{$$help{$$2//'options'}},[$$1,$$3] \
	if/^([\w-_]+)\s*:.*\#\#(?:@(\w+))?\s(.*)$$/}; \
	print"\033[1m$$_:\033[0m\n", map"  \033[36m$$_->[0]\033[0m".(" "x(20-length($$_->[0])))."$$_->[1]\n",\
	@{$$help{$$_}},"\n" for keys %help; \

.PHONY: help-default
help-default: ##@General Show this help
	@echo -e "Usage: make \033[36m<target>\033[0m\n"
	@perl -e '$(HELP_FUN)' $(MAKEFILE_LIST)

YQ_VERSION ?= v4.43.1
YQ ?= $(TOOLBIN)/yq-$(YQ_VERSION)
.PHONY: yq
yq: ##@Setup Download yq locally if necessary.
	$(call go-install-tool,$(YQ),github.com/mikefarah/yq/v4,$(YQ_VERSION))

.PHONY: download-release-yaml-default
download-release-yaml-default: yq ##@Development Download the release yaml
	@# Download the release.yaml
	$(call download-file,$(RELEASE_YAML),$(RELEASE_YAML_PATH))
	@# Format the YAML for easier image replacement later
	$(YQ) eval -P -i $(RELEASE_YAML_PATH)

.PHONY: update-component-version-default
update-component-version-default: yq ##@Development Update the component version
	@echo "Update the version to $(NEW_COMPONENT_VERSION)"
	$(YQ) eval '.global.version = "$(NEW_COMPONENT_VERSION)"' -i values.yaml
	$(YQ) eval "(select(.kind == \"ConfigMap\" and .metadata.name == \"$(VERSION_CONFIGMAP_NAME)\") | .data.version) = \"$(NEW_COMPONENT_VERSION)\"" -i $(RELEASE_YAML_PATH)

CONTROLLER_TOOLS_VERSION ?= v0.17.1
CONTROLLER_GEN ?= $(TOOLBIN)/controller-gen-$(CONTROLLER_TOOLS_VERSION)
.PHONY: controller-gen
controller-gen: ##@Setup Download controller-gen locally if necessary.
	$(call go-install-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen,$(CONTROLLER_TOOLS_VERSION))

.PHONY: generate-crd-docs-default
generate-crd-docs-default: controller-gen ##@Development Generate CRD for docs/shared/crds.
	$(CONTROLLER_GEN) crd:allowDangerousTypes=true paths=./upstream/pkg/apis/... output:crd:artifacts:config=docs/shared/crds

.PHONY: save-new-patch-default
save-new-patch-default: ##@Patch 将upstream(submodule)的变更保存为patch文件并清空变更
	@mkdir -p .tekton/patches
	@cd upstream && git add --all
	@cd upstream && git diff --cached > ../.tekton/patches/new.patch
	@make clean-patches-default

.PHONY: apply-patches-default
# PATCHES: 指定要应用的patch文件列表，多个文件用空格分隔。例如：PATCHES="patch1.yaml patch2.yaml"
# 如果不指定，则应用所有patch文件
PATCHES ?= $(wildcard .tekton/patches/*.patch)
# APPLY_REJECT: 设置为任意非空值以启用 --reject 选项，将无法应用的补丁保存为 .rej 文件
# 例如: make apply-patches APPLY_REJECT=1
APPLY_REJECT ?=
apply-patches-default: ##@Patch 将patches应用到upstream子模块，可通过PATCHES指定具体文件
	@cd upstream && \
    set -e; \
	for patch in $(PATCHES); do \
		if [ -f "../$$patch" ]; then \
			echo "Applying $$patch ..."; \
			git apply $(if $(APPLY_REJECT),--reject,) "../$$patch"; \
		else \
			echo "Warning: Patch file $$patch not found"; \
		fi \
	done

.PHONY: upgrade-go-dependencies-default
upgrade-go-dependencies-default: ##@Development Upgrade go dependencies to fix vulnerabilities
	@cd upstream && \
		if [ -d "vendor" ]; then \
			if git diff --quiet vendor/; then \
				echo "No changes in vendor directory"; \
			else \
				git diff vendor/ | cat; \
				echo -e "\033[31mWarning: There are uncommitted changes in [./upstream/vendor] directory that will be overwritten!\033[0m"; \
				exit 1; \
			fi; \
		fi && \
		for script in ../.tekton/patches/[0-9]*.sh; do \
			if [ -f "$$script" ]; then \
				echo "Executing $$(basename "$$script")..."; \
				bash -x "$$script" || { echo "Failed to execute $$script"; exit 1; }; \
			fi; \
		done

.PHONY: clean-patches-default
clean-patches-default: ##@Patch 清理patch对upstream的变更
	@cd upstream && git reset --hard HEAD
	@cd upstream && git clean -fd
	@# This command initializes and updates the "upstream" Git submodule recursively.
	@git submodule update --init --recursive upstream

.PHONY: sync-submodule-default
sync-submodule-default: ##@Submodule 同步submodule URL并更新到远程分支（用于切换仓库地址后）
	@echo "Syncing submodule URL..."
	@git submodule sync --recursive
	@echo "Updating submodule to remote branch..."
	@git submodule update --init --recursive --remote
	@echo "Submodule sync and update completed"

.PHONY: deploy-defauilt
deploy-default:
	cat release/release.yaml | sed "s/build-harbor.alauda.cn/registry.alauda.cn:60070/g" | kubectl apply -f -

.PHONY: undeploy-default
undeploy-default:
	cat release/release.yaml | kubectl delete -f -

KUSTOMIZE_VERSION ?= v5.3.0
KUSTOMIZE ?= $(TOOLBIN)/kustomize-$(KUSTOMIZE_VERSION)
kustomize: ##@Setup Download kustomize locally if necessary.
	$(call go-install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5,$(KUSTOMIZE_VERSION))

VULNCHECK_DB ?= https://vuln.go.dev
VULNCHECK_MODE ?= source
VULNCHECK_DIR ?= upstream
VULNCHECK_PATH ?= ./...
VULNCHECK_OUTPUT ?= vulncheck.txt
vulncheck: govulncheck ##@Development Run govulncheck against code. Check base.mk file for available envvars
	$(GOVULNCHECK) -db=$(VULNCHECK_DB) -mode=$(VULNCHECK_MODE) -C $(VULNCHECK_DIR) $(VULNCHECK_PATH) | tee $(VULNCHECK_OUTPUT)

GOVULNCHECK_VERSION ?= master
GOVULNCHECK ?= $(TOOLBIN)/govulncheck-$(GOVULNCHECK_VERSION)
govulncheck: ##@Setup Download govulncheck locally if necessary.
# using master until 1.0.5 is released, https://github.com/golang/go/issues/66139
	$(call go-install-tool,$(GOVULNCHECK),golang.org/x/vuln/cmd/govulncheck,$(GOVULNCHECK_VERSION))

# resolve-github-release-version resolves GitHub release version from "latest" or a specified value.
# $1 - requested version (for example: latest, v0.1.0)
# $2 - GitHub repo (for example: owner/repo)
define resolve-github-release-version
if [ "$(1)" = "latest" ]; then \
	echo "Resolving latest version via GitHub release redirect..."; \
	LATEST_RELEASE_URL="https://github.com/$(2)/releases/latest"; \
	RESOLVED_URL=$$(curl --retry 6 --fail --silent --show-error --location --head --output /dev/null --write-out '%{url_effective}' "$$LATEST_RELEASE_URL" || true); \
	if [ -z "$$RESOLVED_URL" ]; then \
		RESOLVED_URL=$$(curl --retry 6 --fail --silent --show-error --location --output /dev/null --write-out '%{url_effective}' "$$LATEST_RELEASE_URL" || true); \
	fi; \
	VERSION=$$(printf '%s\n' "$$RESOLVED_URL" | sed -n 's#^.*/releases/tag/\([^/?#]*\).*#\1#p'); \
	if [ -z "$$VERSION" ]; then \
		echo "Error: Failed to resolve latest version from $$LATEST_RELEASE_URL"; \
		exit 1; \
	fi; \
	echo "Latest version: $$VERSION"; \
else \
	echo "Using specified version: $(1)"; \
	VERSION="$(1)"; \
fi;
endef

# detect-download-platform normalizes local OS/ARCH for release artifact naming.
define detect-download-platform
OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
ARCH=$$(uname -m); \
if [ "$$ARCH" = "x86_64" ]; then ARCH="amd64"; fi; \
if [ "$$ARCH" = "aarch64" ]; then ARCH="arm64"; fi;
endef

# executable-artifact-check-fn defines a shell helper that validates
# downloaded or installed CLI artifacts on both Linux and macOS.
define executable-artifact-check-fn
is_executable_artifact() { \
	_iea_path="$$1"; \
	[ -f "$$_iea_path" ] || return 1; \
	[ -x "$$_iea_path" ] || return 1; \
	if command -v file >/dev/null 2>&1; then \
		file "$$_iea_path" | grep -Eq 'executable|shared library|script text'; \
		return $$?; \
	fi; \
	_iea_magic=$$(LC_ALL=C od -An -N 4 -t x1 "$$_iea_path" 2>/dev/null | tr -d ' \n'); \
	case "$$_iea_magic" in \
		7f454c46|cffaedfe|feedfacf|cafebabe|bebafeca|2321*) return 0 ;; \
	esac; \
	return 1; \
};
endef

# download-github-cli-binary downloads a GitHub release binary artifact and stores a version marker file.
# $1 - cli name (for log/output file name)
# $2 - requested version (latest or explicit)
# $3 - GitHub repo
# $4 - version file path
# $5 - asset file template (can use $$VERSION/$$OS/$$ARCH variables)
define download-github-cli-binary
@echo "Checking $(1)..."
@mkdir -p $(TOOLBIN)
@set -e; \
$(call executable-artifact-check-fn) \
$(call resolve-github-release-version,$(2),$(3)) \
BIN_FILE="$(TOOLBIN)/$(1)-$$VERSION"; \
if [ -f "$$BIN_FILE" ] && ! is_executable_artifact "$$BIN_FILE"; then \
	echo "Existing $(1) $$VERSION artifact at $$BIN_FILE is not executable, removing it..."; \
	rm -f "$$BIN_FILE"; \
fi; \
if [ ! -f "$$BIN_FILE" ]; then \
	$(call detect-download-platform) \
	DOWNLOAD_URL="https://github.com/$(3)/releases/download/$$VERSION/$(5)"; \
	TMP_FILE="$$(mktemp)"; \
	echo "Downloading from $$DOWNLOAD_URL..."; \
	if ! curl --retry 6 --fail -L -o "$$TMP_FILE" "$$DOWNLOAD_URL"; then \
		rm -f "$$TMP_FILE"; \
		exit 1; \
	fi; \
	chmod +x "$$TMP_FILE"; \
	if ! is_executable_artifact "$$TMP_FILE"; then \
		echo "Error: Downloaded $(1) $$VERSION artifact is not executable"; \
		rm -f "$$TMP_FILE"; \
		exit 1; \
	fi; \
	mv "$$TMP_FILE" "$$BIN_FILE"; \
	echo "$$VERSION" > "$(4)"; \
	echo "$(1) $$VERSION downloaded successfully to $$BIN_FILE"; \
else \
	echo "$(1) $$VERSION already exists at $$BIN_FILE"; \
	echo "$$VERSION" > "$(4)"; \
fi
endef

# download-github-cli-archive downloads and extracts a GitHub release archive, then installs the executable.
# $1 - cli name (for log/output file name)
# $2 - requested version (latest or explicit)
# $3 - GitHub repo
# $4 - version file path
# $5 - archive asset template (can use $$VERSION/$$VERSION_NO_PREFIX/$$OS/$$ARCH variables)
# $6 - candidate executable names in archive (space-separated)
define download-github-cli-archive
@echo "Checking $(1)..."
@mkdir -p $(TOOLBIN)
@set -e; \
$(call executable-artifact-check-fn) \
$(call resolve-github-release-version,$(2),$(3)) \
BIN_FILE="$(TOOLBIN)/$(1)-$$VERSION"; \
if [ -f "$$BIN_FILE" ] && ! is_executable_artifact "$$BIN_FILE"; then \
	echo "Existing $(1) $$VERSION artifact at $$BIN_FILE is not executable, removing it..."; \
	rm -f "$$BIN_FILE"; \
fi; \
if [ ! -f "$$BIN_FILE" ]; then \
	$(call detect-download-platform) \
	VERSION_NO_PREFIX=$$(echo "$$VERSION" | sed 's/^v//'); \
	DOWNLOAD_URL="https://github.com/$(3)/releases/download/$$VERSION/$(5)"; \
	echo "Downloading from $$DOWNLOAD_URL..."; \
	TMP_DIR=$$(mktemp -d); \
	ARCHIVE_FILE="$$TMP_DIR/$(1).tar.gz"; \
	if ! curl --retry 6 --fail -L -o "$$ARCHIVE_FILE" "$$DOWNLOAD_URL"; then \
		rm -rf "$$TMP_DIR"; \
		exit 1; \
	fi; \
	tar -xzf "$$ARCHIVE_FILE" -C "$$TMP_DIR"; \
	SRC_BIN=""; \
	for candidate in $(6); do \
		SRC_BIN=$$(find "$$TMP_DIR" -maxdepth 2 -type f -name "$$candidate" | head -n 1); \
		if [ -n "$$SRC_BIN" ]; then \
			break; \
		fi; \
	done; \
	if [ -z "$$SRC_BIN" ]; then \
		echo "Error: Failed to locate $(1) executable in downloaded archive"; \
		rm -rf "$$TMP_DIR"; \
		exit 1; \
	fi; \
	cp "$$SRC_BIN" "$$BIN_FILE"; \
	chmod +x "$$BIN_FILE"; \
	if ! is_executable_artifact "$$BIN_FILE"; then \
		echo "Error: Downloaded $(1) $$VERSION artifact is not executable"; \
		rm -rf "$$TMP_DIR"; \
		rm -f "$$BIN_FILE"; \
		exit 1; \
	fi; \
	rm -rf "$$TMP_DIR"; \
	echo "$$VERSION" > "$(4)"; \
	echo "$(1) $$VERSION downloaded successfully to $$BIN_FILE"; \
else \
	echo "$(1) $$VERSION already exists at $$BIN_FILE"; \
	echo "$$VERSION" > "$(4)"; \
fi
endef

# Default to the latest release resolved via GitHub's release redirect.
# Override with an explicit version like "v0.2.2" for reproducible local runs.
GITLAB_CLI_VERSION ?= latest
GITLAB_CLI_REPO ?= AlaudaDevops/gitlab-cli
GITLAB_CLI_VERSION_FILE ?= $(TOOLBIN)/.gitlab-cli-$(GITLAB_CLI_VERSION)
# Get the installed version; return empty if not present
GITLAB_CLI_INSTALLED_VERSION = $(shell [ -f "$(GITLAB_CLI_VERSION_FILE)" ] && cat "$(GITLAB_CLI_VERSION_FILE)" || echo "")
# Use the installed version as the binary name; otherwise use the generic name
GITLAB_CLI_BIN = $(TOOLBIN)/gitlab-cli$(if $(GITLAB_CLI_INSTALLED_VERSION),-$(GITLAB_CLI_INSTALLED_VERSION),)
.PHONY: download-gitlab-cli
download-gitlab-cli:
	$(call download-github-cli-binary,gitlab-cli,$(GITLAB_CLI_VERSION),$(GITLAB_CLI_REPO),$(GITLAB_CLI_VERSION_FILE),gitlab-cli-$$OS-$$ARCH)

PREPARE_DATA_DIR ?= testing
TESTING_CONFIG ?= $(PREPARE_DATA_DIR)/config.yaml

# ensure-testing-config creates the shared testing config when it does not exist yet.
define ensure-testing-config
@if [ ! -f "$(TESTING_CONFIG)" ]; then \
	echo "Creating initial $(TESTING_CONFIG)..."; \
	echo "toolchains: {}" > "$(TESTING_CONFIG)"; \
fi
endef

# merge-generated-toolchain-config merges one generated toolchain subtree into TESTING_CONFIG.
# $1 - toolchain name
# $2 - generated config path
define merge-generated-toolchain-config
@echo "Merging $(1) config into $(TESTING_CONFIG)..."
$(call ensure-testing-config)
@$(YQ) eval '.toolchains.$(1) = load("$(2)").toolchains.$(1)' -i "$(TESTING_CONFIG)"
endef

GITLAB_USERS_FILE ?= $(PREPARE_DATA_DIR)/config/users.yaml
GITLAB_TEMPLATE_FILE ?= $(PREPARE_DATA_DIR)/config/gitlab-template.yaml
GENERATED_GITLAB_USERS_FILE ?= $(PREPARE_DATA_DIR)/config/users-generated.yaml
# Prepare test data: use gitlab-cli to create users, groups, and projects from users.yaml
# Use nameMode: prefix; gitlab-cli appends a timestamp to username, email, group path, project path
# Required environment variables:
# GITLAB_URL - GitLab instance URL (e.g., https://gitlab.example.com)
# GITLAB_TOKEN - GitLab Personal Access Token (needs api + sudo permissions)
.PHONY: prepare-gitlab-data
prepare-gitlab-data: download-gitlab-cli yq
	@echo "Preparing test data using gitlab-cli..."
	@if [ -z "$(GITLAB_URL)" ]; then \
		echo "Error: GITLAB_URL environment variable is not set"; \
		echo "Usage: GITLAB_URL=https://gitlab.example.com GITLAB_TOKEN=your-token make prepare-gitlab-data"; \
		exit 1; \
	fi
	@if [ -z "$(GITLAB_TOKEN)" ]; then \
		echo "Error: GITLAB_TOKEN environment variable is not set"; \
		echo "Usage: GITLAB_URL=https://gitlab.example.com GITLAB_TOKEN=your-token make prepare-gitlab-data"; \
		exit 1; \
	fi
	@echo "Using gitlab-cli at $(GITLAB_CLI_BIN)"
	@echo "Running gitlab-cli in prefix mode (auto-generates timestamp)..."
	@$(GITLAB_CLI_BIN) user create -f $(GITLAB_USERS_FILE) -o $(GENERATED_GITLAB_USERS_FILE) -t $(GITLAB_TEMPLATE_FILE)
	$(call merge-generated-toolchain-config,gitlab,$(GENERATED_GITLAB_USERS_FILE))
	@echo "Data preparation completed"
	@echo "GitLab config merged into $(TESTING_CONFIG)"
	@echo "Generated users config saved to $(GENERATED_GITLAB_USERS_FILE)"
	@echo "⚠️  Note: For cleanup, use the generated file: make clean-data"

# Default to the latest release resolved via GitHub's release redirect.
# Override with an explicit version like "v0.3.1" for reproducible local runs.
NEXUS_CLI_VERSION ?= latest
NEXUS_CLI_REPO ?= AlaudaDevops/nexus-cli
NEXUS_CLI_VERSION_FILE ?= $(TOOLBIN)/.nexus-cli-$(NEXUS_CLI_VERSION)
# Get the installed version; return empty if not present
NEXUS_CLI_INSTALLED_VERSION = $(shell [ -f "$(NEXUS_CLI_VERSION_FILE)" ] && cat "$(NEXUS_CLI_VERSION_FILE)" || echo "")
# Use the installed version as the binary name; otherwise use the generic name
NEXUS_CLI = $(TOOLBIN)/nexus-cli$(if $(NEXUS_CLI_INSTALLED_VERSION),-$(NEXUS_CLI_INSTALLED_VERSION),)
.PHONY: download-nexus-cli
download-nexus-cli:
	$(call download-github-cli-binary,nexus-cli,$(NEXUS_CLI_VERSION),$(NEXUS_CLI_REPO),$(NEXUS_CLI_VERSION_FILE),nexus-cli-$$OS-$$ARCH)

NEXUS_USERS_FILE ?= $(PREPARE_DATA_DIR)/config/nexus-users.yaml
NEXUS_TEMPLATE_FILE ?= $(PREPARE_DATA_DIR)/config/nexus-template.yaml
GENERATED_NEXUS_USERS_FILE ?= $(PREPARE_DATA_DIR)/config/nexus-users-generated.yaml
GENERATED_NEXUS_RESOURCES_FILE ?= $(PREPARE_DATA_DIR)/config/nexus-users-runtime.yaml
# Prepare Nexus test data: use nexus-cli to create repositories, roles, and users from nexus-users.yaml
# Persist resolved names to GENERATED_NEXUS_RESOURCES_FILE for deterministic cleanup in nameMode=suffix.
# Required environment variables:
# NEXUS_URL - Nexus instance URL (e.g., https://nexus.example.com)
# NEXUS_USERNAME - Nexus username with permission to create roles and users
# NEXUS_PASSWORD - Password for the above user
.PHONY: prepare-nexus-data
prepare-nexus-data: download-nexus-cli yq
	@echo "Preparing Nexus test data using nexus-cli..."
	@if [ -z "$(NEXUS_URL)" ]; then \
		echo "Error: NEXUS_URL environment variable is not set"; \
		echo "Usage: NEXUS_URL=https://nexus.example.com NEXUS_USERNAME=user NEXUS_PASSWORD=password make prepare-nexus-data"; \
		exit 1; \
	fi
	@if [ -z "$(NEXUS_USERNAME)" ]; then \
		echo "Error: NEXUS_USERNAME environment variable is not set"; \
		echo "Usage: NEXUS_URL=https://nexus.example.com NEXUS_USERNAME=user NEXUS_PASSWORD=password make prepare-nexus-data"; \
		exit 1; \
	fi
	@if [ -z "$(NEXUS_PASSWORD)" ]; then \
		echo "Error: NEXUS_PASSWORD environment variable is not set"; \
		echo "Usage: NEXUS_URL=https://nexus.example.com NEXUS_USERNAME=user NEXUS_PASSWORD=password make prepare-nexus-data"; \
		exit 1; \
	fi
	@echo "Using nexus-cli at $(NEXUS_CLI)"
	@echo "Running nexus-cli to create repositories, roles, and users..."
	@export NEXUS_URL="$(NEXUS_URL)"; \
	export NEXUS_USERNAME="$(NEXUS_USERNAME)"; \
	export NEXUS_PASSWORD="$(NEXUS_PASSWORD)"; \
	$(NEXUS_CLI) create \
		--config $(NEXUS_USERS_FILE) \
		--resolved-config $(GENERATED_NEXUS_RESOURCES_FILE) \
		--output-template $(NEXUS_TEMPLATE_FILE) \
		--output-file $(GENERATED_NEXUS_USERS_FILE)
	$(call merge-generated-toolchain-config,nexus,$(GENERATED_NEXUS_USERS_FILE))
	@echo "Data preparation completed"
	@echo "Nexus config merged into $(TESTING_CONFIG)"
	@echo "Generated Nexus runtime config saved to $(GENERATED_NEXUS_RESOURCES_FILE)"
	@echo "Generated users config saved to $(GENERATED_NEXUS_USERS_FILE)"

# Default to the latest release resolved via GitHub's release redirect.
# Override with an explicit version like "v0.0.19" for reproducible local runs.
HARBOR_CLI_VERSION ?= latest
HARBOR_CLI_REPO ?= goharbor/harbor-cli
HARBOR_CLI_VERSION_FILE ?= $(TOOLBIN)/.harbor-cli-$(HARBOR_CLI_VERSION)
# Get the installed version; return empty if not present
HARBOR_CLI_INSTALLED_VERSION = $(shell [ -f "$(HARBOR_CLI_VERSION_FILE)" ] && cat "$(HARBOR_CLI_VERSION_FILE)" || echo "")
# Use the installed version as the binary name; otherwise use the generic name
HARBOR_CLI = $(TOOLBIN)/harbor-cli$(if $(HARBOR_CLI_INSTALLED_VERSION),-$(HARBOR_CLI_INSTALLED_VERSION),)
.PHONY: download-harbor-cli
download-harbor-cli:
	$(call download-github-cli-archive,harbor-cli,$(HARBOR_CLI_VERSION),$(HARBOR_CLI_REPO),$(HARBOR_CLI_VERSION_FILE),harbor-cli_$${VERSION_NO_PREFIX}_$${OS}_$${ARCH}.tar.gz,harbor harbor-cli)

HARBOR_ROBOT_TEMPLATE_FILE ?= $(PREPARE_DATA_DIR)/config/harbor-robot-template.yaml
HARBOR_ROBOT_GENERATED_FILE ?= $(PREPARE_DATA_DIR)/config/harbor-robot-generated.yaml
HARBOR_GENERATED_FILE ?= $(PREPARE_DATA_DIR)/config/harbor-generated.yaml
HARBOR_RUNTIME_FILE ?= $(PREPARE_DATA_DIR)/config/harbor-runtime.yaml
HARBOR_CLI_CONFIG_FILE ?= $(PREPARE_DATA_DIR)/config/harbor-cli-config.yaml
HARBOR_ROBOT_SECRET_FILE ?= $(PREPARE_DATA_DIR)/config/harbor-robot-secret.json
HARBOR_TEST_PROJECT_PREFIX ?= tekton-e2e
HARBOR_ROBOT_NAME_PREFIX ?= tekton-e2e-robot
HARBOR_ROBOT_DURATION_DAYS ?= 7
# Some integration test cases depend on this project existing in Harbor (e.g. for image push/pull).
# It is created idempotently here so that robot provisioning and downstream test cases do not fail
# when the project is absent. This file is also consumed by the tektoncd-operator repo.
HARBOR_OPS_PROJECT ?= ops
# Automation e2e suites rely on this project existing in Harbor as well.
# Created idempotently alongside the ops project so robot provisioning and
# downstream test cases do not fail when the project is absent.
HARBOR_E2E_AUTOMATION_PROJECT ?= e2e-automation
# Prepare Harbor test data:
# 1. login by bootstrap account
# 2. create run-unique test project
# 3. create robot account and generate runtime config for cleanup
# Required environment variables:
# HARBOR_URL - Harbor endpoint (e.g., https://harbor.example.com)
# HARBOR_HOST - Harbor host (e.g., harbor.example.com)
# HARBOR_PORT - Harbor port (e.g., 443)
# HARBOR_SCHEME - Harbor scheme (http or https)
# HARBOR_USERNAME - bootstrap username with permission to create project/robot
# HARBOR_PASSWORD - bootstrap password
.PHONY: prepare-harbor-data
prepare-harbor-data: download-harbor-cli yq
	@echo "Preparing Harbor test data using harbor-cli..."
	@if [ -z "$(HARBOR_URL)" ]; then \
		echo "Error: HARBOR_URL environment variable is not set"; \
		echo "Usage: HARBOR_URL=https://harbor.example.com HARBOR_HOST=harbor.example.com HARBOR_PORT=443 HARBOR_SCHEME=https HARBOR_USERNAME=admin HARBOR_PASSWORD=password make prepare-harbor-data"; \
		exit 1; \
	fi
	@if [ -z "$(HARBOR_USERNAME)" ]; then \
		echo "Error: HARBOR_USERNAME environment variable is not set"; \
		echo "Usage: HARBOR_URL=https://harbor.example.com HARBOR_HOST=harbor.example.com HARBOR_PORT=443 HARBOR_SCHEME=https HARBOR_USERNAME=admin HARBOR_PASSWORD=password make prepare-harbor-data"; \
		exit 1; \
	fi
	@if [ -z "$(HARBOR_PASSWORD)" ]; then \
		echo "Error: HARBOR_PASSWORD environment variable is not set"; \
		echo "Usage: HARBOR_URL=https://harbor.example.com HARBOR_HOST=harbor.example.com HARBOR_PORT=443 HARBOR_SCHEME=https HARBOR_USERNAME=admin HARBOR_PASSWORD=password make prepare-harbor-data"; \
		exit 1; \
	fi
	@if [ ! -f "$(HARBOR_ROBOT_TEMPLATE_FILE)" ]; then \
		echo "Error: $(HARBOR_ROBOT_TEMPLATE_FILE) not found"; \
		exit 1; \
	fi
	@if [ -z "$(HARBOR_HOST)" ]; then \
		echo "Error: HARBOR_HOST environment variable is not set"; \
		echo "Usage: HARBOR_URL=https://harbor.example.com HARBOR_HOST=harbor.example.com HARBOR_PORT=443 HARBOR_SCHEME=https HARBOR_USERNAME=admin HARBOR_PASSWORD=password make prepare-harbor-data"; \
		exit 1; \
	fi
	@if [ -z "$(HARBOR_PORT)" ]; then \
		echo "Error: HARBOR_PORT environment variable is not set"; \
		echo "Usage: HARBOR_URL=https://harbor.example.com HARBOR_HOST=harbor.example.com HARBOR_PORT=443 HARBOR_SCHEME=https HARBOR_USERNAME=admin HARBOR_PASSWORD=password make prepare-harbor-data"; \
		exit 1; \
	fi
	@if [ -z "$(HARBOR_SCHEME)" ]; then \
		echo "Error: HARBOR_SCHEME environment variable is not set"; \
		echo "Usage: HARBOR_URL=https://harbor.example.com HARBOR_HOST=harbor.example.com HARBOR_PORT=443 HARBOR_SCHEME=https HARBOR_USERNAME=admin HARBOR_PASSWORD=password make prepare-harbor-data"; \
		exit 1; \
	fi
	@echo "Using harbor-cli at $(HARBOR_CLI)"
	@set -e; \
	export HARBOR_ROBOT_DURATION_DAYS="$(HARBOR_ROBOT_DURATION_DAYS)"; \
	RUN_SUFFIX=$$(date +%Y%m%d%H%M%S)-$${RANDOM}; \
	PROJECT_NAME="$(HARBOR_TEST_PROJECT_PREFIX)-$$RUN_SUFFIX"; \
	ROBOT_NAME="$(HARBOR_ROBOT_NAME_PREFIX)-$$RUN_SUFFIX"; \
	export PROJECT_NAME ROBOT_NAME; \
	$(HARBOR_CLI) --config "$(HARBOR_CLI_CONFIG_FILE)" login "$(HARBOR_URL)" -u "$(HARBOR_USERNAME)" -p "$(HARBOR_PASSWORD)"; \
	$(HARBOR_CLI) --config "$(HARBOR_CLI_CONFIG_FILE)" project create "$$PROJECT_NAME" --storage-limit "-1"; \
	$(HARBOR_CLI) --config "$(HARBOR_CLI_CONFIG_FILE)" project create "$(HARBOR_OPS_PROJECT)" --storage-limit "-1" 2>/dev/null || echo "Harbor '$(HARBOR_OPS_PROJECT)' project already exists, skipping"; \
	$(HARBOR_CLI) --config "$(HARBOR_CLI_CONFIG_FILE)" project create "$(HARBOR_E2E_AUTOMATION_PROJECT)" --storage-limit "-1" 2>/dev/null || echo "Harbor '$(HARBOR_E2E_AUTOMATION_PROJECT)' project already exists, skipping"; \
	cp "$(HARBOR_ROBOT_TEMPLATE_FILE)" "$(HARBOR_ROBOT_GENERATED_FILE)"; \
	$(YQ) eval '.name = env(ROBOT_NAME)' -i "$(HARBOR_ROBOT_GENERATED_FILE)"; \
	$(YQ) eval '.duration = (env(HARBOR_ROBOT_DURATION_DAYS) | tonumber)' -i "$(HARBOR_ROBOT_GENERATED_FILE)"; \
	$(YQ) eval '.permissions[1].namespace = env(PROJECT_NAME)' -i "$(HARBOR_ROBOT_GENERATED_FILE)"; \
	$(YQ) eval '.permissions[2].namespace = "$(HARBOR_OPS_PROJECT)"' -i "$(HARBOR_ROBOT_GENERATED_FILE)"; \
	$(YQ) eval '.permissions[3].namespace = "$(HARBOR_E2E_AUTOMATION_PROJECT)"' -i "$(HARBOR_ROBOT_GENERATED_FILE)"; \
	rm -f "$(PREPARE_DATA_DIR)/config/"*"$$ROBOT_NAME"*"secret.json"; \
	( cd "$(PREPARE_DATA_DIR)/config" && "$(abspath $(HARBOR_CLI))" --config "$(abspath $(HARBOR_CLI_CONFIG_FILE))" robot create --robot-config-file "$(notdir $(HARBOR_ROBOT_GENERATED_FILE))" --export-to-file ); \
	SECRET_FILE=$$(ls -1t "$(PREPARE_DATA_DIR)/config/"*"$$ROBOT_NAME"*"secret.json" 2>/dev/null | head -n 1); \
	if [ -z "$$SECRET_FILE" ]; then \
		echo "Error: Failed to locate generated Harbor robot secret file"; \
		exit 1; \
	fi; \
	mv -f "$$SECRET_FILE" "$(HARBOR_ROBOT_SECRET_FILE)"; \
	ROBOT_USERNAME=$$($(YQ) eval -r '.name' "$(HARBOR_ROBOT_SECRET_FILE)"); \
	ROBOT_PASSWORD=$$($(YQ) eval -r '.secret' "$(HARBOR_ROBOT_SECRET_FILE)"); \
	if [ -z "$$ROBOT_USERNAME" ] || [ "$$ROBOT_USERNAME" = "null" ] || [ -z "$$ROBOT_PASSWORD" ] || [ "$$ROBOT_PASSWORD" = "null" ]; then \
		echo "Error: Failed to parse robot credentials from $(HARBOR_ROBOT_SECRET_FILE)"; \
		exit 1; \
	fi; \
	export ROBOT_USERNAME ROBOT_PASSWORD; \
	AUTH_B64=$$(printf "%s:%s" "$$ROBOT_USERNAME" "$$ROBOT_PASSWORD" | base64 | tr -d '\n'); \
	DOCKER_JSON=$$(printf '{"auths":{"%s":{"auth":"%s"},"%s:%s":{"auth":"%s"}}}' "$(HARBOR_HOST)" "$$AUTH_B64" "$(HARBOR_HOST)" "$(HARBOR_PORT)" "$$AUTH_B64"); \
	DOCKER_CONFIG_B64=$$(printf "%s" "$$DOCKER_JSON" | base64 | tr -d '\n'); \
	export DOCKER_CONFIG_B64; \
	$(YQ) -n '.toolchains.harbor.endpoint = "$(HARBOR_URL)" | .toolchains.harbor.host = "$(HARBOR_HOST)" | .toolchains.harbor.port = $(HARBOR_PORT) | .toolchains.harbor.scheme = "$(HARBOR_SCHEME)" | .toolchains.harbor.username = strenv(ROBOT_USERNAME) | .toolchains.harbor.password = strenv(ROBOT_PASSWORD) | .toolchains.harbor.testGroup.default = strenv(PROJECT_NAME) | .toolchains.harbor.dockerConfig = strenv(DOCKER_CONFIG_B64) | .toolchains.harbor.containerConfig = strenv(DOCKER_CONFIG_B64)' > "$(HARBOR_GENERATED_FILE)"; \
	GENERATED_AT=$$(date -Iseconds); \
	export GENERATED_AT; \
	$(YQ) -n '.harbor.endpoint = "$(HARBOR_URL)" | .harbor.project = strenv(PROJECT_NAME) | .harbor.robot.level = "system" | .harbor.robot.name = strenv(ROBOT_USERNAME) | .harbor.robot.secretFile = "$(HARBOR_ROBOT_SECRET_FILE)" | .harbor.generatedAt = strenv(GENERATED_AT)' > "$(HARBOR_RUNTIME_FILE)"
	$(call merge-generated-toolchain-config,harbor,$(HARBOR_GENERATED_FILE))
	@echo "Harbor data preparation completed"
	@echo "Harbor config merged into $(TESTING_CONFIG)"
	@echo "Generated Harbor runtime config saved to $(HARBOR_RUNTIME_FILE)"
	@echo "Generated Harbor robot config saved to $(HARBOR_ROBOT_GENERATED_FILE)"
	@echo "Generated Harbor users config saved to $(HARBOR_GENERATED_FILE)"

# Clean GitLab test data: read usernames from the generated YAML file and delete users
# Required environment variables: GITLAB_URL and GITLAB_TOKEN
.PHONY: clean-gitlab-data
clean-gitlab-data: download-gitlab-cli
	@echo "Cleaning up test data using gitlab-cli..."
	@if [ ! -f "$(GITLAB_CLI_BIN)" ]; then \
		echo "Error: gitlab-cli not found. Please run 'make prepare-gitlab-data' first."; \
		exit 1; \
	fi
	@if [ ! -f "$(GENERATED_GITLAB_USERS_FILE)" ]; then \
		echo "Warning: $(GENERATED_GITLAB_USERS_FILE) not found. Cannot delete user."; \
		echo "If you want to delete manually, please specify the username."; \
		exit 1; \
	fi
	@echo "Extracting username from $(GENERATED_GITLAB_USERS_FILE)..."
	@USERNAME=$$(yq eval '.toolchains.gitlab.username' $(GENERATED_GITLAB_USERS_FILE)); \
	if [ -z "$$USERNAME" ] || [ "$$USERNAME" = "null" ]; then \
		echo "Error: Could not extract username from $(GENERATED_GITLAB_USERS_FILE)"; \
		exit 1; \
	fi; \
	echo "Deleting user: $$USERNAME"; \
	$(GITLAB_CLI_BIN) user delete --username "$$USERNAME"; \
	if [ $$? -eq 0 ]; then \
		rm -f $(GENERATED_GITLAB_USERS_FILE); \
		echo "Removed $(GENERATED_GITLAB_USERS_FILE)"; \
		echo "Data cleanup completed"; \
	else \
		echo "Error: Failed to delete user $$USERNAME"; \
		exit 1; \
	fi

# Clean Nexus test data from nexus-users.yaml
# Required environment variables: NEXUS_URL, NEXUS_USERNAME, NEXUS_PASSWORD
.PHONY: clean-nexus-data
clean-nexus-data: download-nexus-cli
	@echo "Cleaning up Nexus test data using nexus-cli..."
	@if [ ! -f "$(NEXUS_CLI)" ]; then \
		echo "Error: nexus-cli not found. Please run 'make prepare-nexus-data' first."; \
		exit 1; \
	fi
	@if [ ! -f "$(NEXUS_USERS_FILE)" ]; then \
		echo "Warning: $(NEXUS_USERS_FILE) not found. Cannot delete users."; \
		echo "If you want to delete manually, please specify the users/resources config."; \
		exit 1; \
	fi
	@DELETE_CONFIG="$(GENERATED_NEXUS_RESOURCES_FILE)"; \
	if [ ! -f "$$DELETE_CONFIG" ]; then \
		echo "Warning: $(GENERATED_NEXUS_RESOURCES_FILE) not found. Falling back to $(NEXUS_USERS_FILE)."; \
		DELETE_CONFIG="$(NEXUS_USERS_FILE)"; \
	fi; \
	$(NEXUS_CLI) delete --config $$DELETE_CONFIG --force; \
	if [ $$? -eq 0 ]; then \
		rm -f $(GENERATED_NEXUS_RESOURCES_FILE); \
		rm -f $(GENERATED_NEXUS_USERS_FILE); \
		echo "Removed $(GENERATED_NEXUS_RESOURCES_FILE)"; \
		echo "Removed $(GENERATED_NEXUS_USERS_FILE)"; \
		echo "Nexus data cleanup completed"; \
	else \
		echo "Error: Failed to clean Nexus data"; \
		exit 1; \
	fi

# Clean Harbor test data from harbor-runtime.yaml
# Required environment variables: HARBOR_URL, HARBOR_USERNAME, HARBOR_PASSWORD
.PHONY: clean-harbor-data
clean-harbor-data: yq download-harbor-cli
	@echo "Cleaning up Harbor test data using harbor-cli..."
	@if [ ! -f "$(HARBOR_CLI)" ]; then \
		echo "Error: harbor-cli not found. Please run 'make prepare-harbor-data' first."; \
		exit 1; \
	fi
	@if [ ! -f "$(HARBOR_RUNTIME_FILE)" ]; then \
		echo "Warning: $(HARBOR_RUNTIME_FILE) not found. Cannot delete project and robot."; \
		echo "If you want to delete manually, please specify the project and robot account."; \
		exit 1; \
	fi
	@set -e; \
	PROJECT_NAME=$$($(YQ) eval '.harbor.project' "$(HARBOR_RUNTIME_FILE)"); \
	ROBOT_ACCOUNT_NAME=$$($(YQ) eval '.harbor.robot.name' "$(HARBOR_RUNTIME_FILE)"); \
	$(HARBOR_CLI) --config "$(HARBOR_CLI_CONFIG_FILE)" login "$(HARBOR_URL)" -u "$(HARBOR_USERNAME)" -p "$(HARBOR_PASSWORD)"; \
	status=0; \
	if [ -n "$$PROJECT_NAME" ] && [ "$$PROJECT_NAME" != "null" ]; then \
		$(HARBOR_CLI) --config "$(HARBOR_CLI_CONFIG_FILE)" project delete "$$PROJECT_NAME" --force || status=1; \
	fi; \
	if [ -n "$$ROBOT_ACCOUNT_NAME" ] && [ "$$ROBOT_ACCOUNT_NAME" != "null" ]; then \
		$(HARBOR_CLI) --config "$(HARBOR_CLI_CONFIG_FILE)" robot delete "$$ROBOT_ACCOUNT_NAME" || status=1; \
	fi; \
	if [ $$status -eq 0 ]; then \
		rm -f "$(HARBOR_RUNTIME_FILE)"; \
		rm -f "$(HARBOR_GENERATED_FILE)"; \
		rm -f "$(HARBOR_ROBOT_GENERATED_FILE)"; \
		rm -f "$(HARBOR_ROBOT_SECRET_FILE)"; \
		rm -f "$(HARBOR_CLI_CONFIG_FILE)"; \
		echo "Harbor data cleanup completed"; \
	else \
		echo "Error: Failed to clean Harbor data"; \
		exit 1; \
	fi

# Default to the latest release resolved via GitHub's release redirect.
# Override with an explicit version like "v0.3.0" for reproducible local runs.
SONARQUBE_CLI_VERSION ?= latest
SONARQUBE_CLI_REPO ?= AlaudaDevops/sonarqube-cli
SONARQUBE_CLI_VERSION_FILE ?= $(TOOLBIN)/.sonarqube-cli-$(SONARQUBE_CLI_VERSION)
SONARQUBE_CLI_INSTALLED_VERSION = $(shell [ -f "$(SONARQUBE_CLI_VERSION_FILE)" ] && cat "$(SONARQUBE_CLI_VERSION_FILE)" || echo "")
SONARQUBE_CLI = $(TOOLBIN)/sonarqube-cli$(if $(SONARQUBE_CLI_INSTALLED_VERSION),-$(SONARQUBE_CLI_INSTALLED_VERSION),)
.PHONY: download-sonarqube-cli
download-sonarqube-cli:
	$(call download-github-cli-binary,sonarqube-cli,$(SONARQUBE_CLI_VERSION),$(SONARQUBE_CLI_REPO),$(SONARQUBE_CLI_VERSION_FILE),sonarqube-cli-$$OS-$$ARCH)

SONARQUBE_RESOURCES_FILE ?= $(PREPARE_DATA_DIR)/config/sonarqube-resources.yaml
SONARQUBE_TEMPLATE_FILE ?= $(PREPARE_DATA_DIR)/config/sonarqube-template.yaml
GENERATED_SONARQUBE_USERS_FILE ?= $(PREPARE_DATA_DIR)/config/sonarqube-users-generated.yaml
GENERATED_SONARQUBE_RUNTIME_FILE ?= $(PREPARE_DATA_DIR)/config/sonarqube-runtime.yaml
GENERATED_SONARQUBE_STATE_FILE ?= $(PREPARE_DATA_DIR)/config/sonarqube-state.yaml
GENERATED_SONARQUBE_TOKEN_FILE ?= $(TOOLBIN)/.sonarqube-token
GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE ?= $(TOOLBIN)/.sonarqube-manager-token
GENERATED_SONARQUBE_TEMP_PASSWORD_INPUT_FILE ?= $(TOOLBIN)/.sonarqube-temp-user-password
# Prepare SonarQube test data: use sonarqube-cli to create projects, roles, and users from sonarqube-resources.yaml
# Required environment variables:
# SONARQUBE_URL - SonarQube instance URL
# SONARQUBE_MANAGER_TOKEN - Manager token with permission to create projects and users
# TEMP_USER_PASSWORD - Password for the temporary test user (min 8 characters)
.PHONY: prepare-sonarqube-data
prepare-sonarqube-data: export SONARQUBE_URL := $(SONARQUBE_URL)
prepare-sonarqube-data: export SONARQUBE_MANAGER_TOKEN := $(SONARQUBE_MANAGER_TOKEN)
prepare-sonarqube-data: export TEMP_USER_PASSWORD := $(TEMP_USER_PASSWORD)
prepare-sonarqube-data: download-sonarqube-cli yq
	@echo "Preparing SonarQube test data using sonarqube-cli..."
	@if [ -z "$$SONARQUBE_URL" ]; then \
		echo "Error: SONARQUBE_URL environment variable is not set"; \
		exit 1; \
	fi
	@if [ -z "$$SONARQUBE_MANAGER_TOKEN" ]; then \
		echo "Error: SONARQUBE_MANAGER_TOKEN environment variable is not set"; \
		exit 1; \
	fi
	@if [ -z "$$TEMP_USER_PASSWORD" ]; then \
		echo "Error: TEMP_USER_PASSWORD environment variable is not set"; \
		exit 1; \
	fi
	@echo "Using sonarqube-cli at $(SONARQUBE_CLI)"
	@# Generate a unique task-run-id using timestamp and random suffix to avoid collisions
	@mkdir -p "$(TOOLBIN)"; \
	printf '%s' "$$SONARQUBE_MANAGER_TOKEN" > "$(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE)"; \
	printf '%s' "$$TEMP_USER_PASSWORD" > "$(GENERATED_SONARQUBE_TEMP_PASSWORD_INPUT_FILE)"; \
	SONAR_E2E_TASK_RUN_ID=$$(date +%s)$${RANDOM}; \
	SONAR_TOKEN_FILE="$(GENERATED_SONARQUBE_TOKEN_FILE)"; \
	trap 'rm -f "$(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE)" "$(GENERATED_SONARQUBE_TEMP_PASSWORD_INPUT_FILE)" "$$SONAR_TOKEN_FILE"' EXIT; \
	chmod 600 "$(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE)" "$(GENERATED_SONARQUBE_TEMP_PASSWORD_INPUT_FILE)"; \
	TEMP_USER_PASSWORD_VALUE=$$(tr -d '\r\n' < "$(GENERATED_SONARQUBE_TEMP_PASSWORD_INPUT_FILE)"); \
	if [ $${#TEMP_USER_PASSWORD_VALUE} -lt 8 ]; then \
		echo "Error: TEMP_USER_PASSWORD must be at least 8 characters long"; \
		exit 1; \
	fi; \
	if ! printf '%s\n' "$$TEMP_USER_PASSWORD_VALUE" | grep -qE '^[a-zA-Z0-9@#%^&*_=+~.-]+$$'; then \
		echo "Error: TEMP_USER_PASSWORD contains invalid characters. Only alphanumeric and @#%^&*_=+~.- are allowed."; \
		exit 1; \
	fi; \
	echo "Running sonarqube-cli to create resources with SONAR_E2E_TASK_RUN_ID: $$SONAR_E2E_TASK_RUN_ID..."; \
	$(SONARQUBE_CLI) resources create \
		--config $(SONARQUBE_RESOURCES_FILE) \
		--task-run-id $$SONAR_E2E_TASK_RUN_ID \
		--plugin tektoncd \
		--manager-token-file "$(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE)" \
		--temp-user-password-file "$(GENERATED_SONARQUBE_TEMP_PASSWORD_INPUT_FILE)" \
		--state-file $(GENERATED_SONARQUBE_STATE_FILE) \
		--resolved-config $(GENERATED_SONARQUBE_RUNTIME_FILE) \
		--output-template $(SONARQUBE_TEMPLATE_FILE) \
		--output-file $(GENERATED_SONARQUBE_USERS_FILE) \
		--token-file "$$SONAR_TOKEN_FILE"; \
	if [ ! -f "$(GENERATED_SONARQUBE_USERS_FILE)" ]; then \
		echo "Error: Generated config file $(GENERATED_SONARQUBE_USERS_FILE) not found"; \
		exit 1; \
	fi
	$(call merge-generated-toolchain-config,sonarqube,$(GENERATED_SONARQUBE_USERS_FILE))
	@echo "SonarQube preparation completed"

.PHONY: clean-sonarqube-data
# Note: state file ($(GENERATED_SONARQUBE_STATE_FILE)) is removed by sonarqube-cli after successful cleanup.
clean-sonarqube-data: export SONARQUBE_URL := $(SONARQUBE_URL)
clean-sonarqube-data: export SONARQUBE_MANAGER_TOKEN := $(SONARQUBE_MANAGER_TOKEN)
clean-sonarqube-data: download-sonarqube-cli
	@echo "Cleaning up SonarQube test data using sonarqube-cli..."
	@if [ -z "$$SONARQUBE_URL" ] || [ -z "$$SONARQUBE_MANAGER_TOKEN" ]; then \
		echo "Error: SONARQUBE_URL/SONARQUBE_MANAGER_TOKEN not set."; \
		exit 1; \
	fi; \
	if [ ! -f "$(GENERATED_SONARQUBE_STATE_FILE)" ]; then \
		echo "Warning: $(GENERATED_SONARQUBE_STATE_FILE) not found. Cannot clean SonarQube resources."; \
		rm -f "$(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE)"; \
		exit 1; \
	fi; \
	mkdir -p "$(TOOLBIN)"; \
	printf '%s' "$$SONARQUBE_MANAGER_TOKEN" > "$(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE)"; \
	echo "Deleting SonarQube resources using $(GENERATED_SONARQUBE_STATE_FILE)..."; \
	trap 'rm -f "$(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE)"' EXIT; \
	chmod 600 "$(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE)"; \
	$(SONARQUBE_CLI) resources cleanup \
		--config $(SONARQUBE_RESOURCES_FILE) \
		--state-file $(GENERATED_SONARQUBE_STATE_FILE) \
		--plugin tektoncd \
		--manager-token-file "$(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE)"; \
	if [ $$? -eq 0 ]; then \
		rm -f $(GENERATED_SONARQUBE_USERS_FILE) $(GENERATED_SONARQUBE_RUNTIME_FILE) $(GENERATED_SONARQUBE_TOKEN_FILE) $(GENERATED_SONARQUBE_MANAGER_TOKEN_INPUT_FILE) $(GENERATED_SONARQUBE_TEMP_PASSWORD_INPUT_FILE); \
		echo "SonarQube cleanup completed"; \
	else \
		echo "Error: Failed to cleanup SonarQube resources. Keeping $(GENERATED_SONARQUBE_STATE_FILE) and $(GENERATED_SONARQUBE_RUNTIME_FILE) for debugging."; \
		exit 1; \
	fi

# Clean all external test data
.PHONY: clean-data
# Best-effort cleanup: run all clean targets even if one fails, then return combined status.
clean-data:
	@set +e; \
	status=0; \
	$(MAKE) clean-gitlab-data || status=1; \
	$(MAKE) clean-nexus-data || status=1; \
	$(MAKE) clean-harbor-data || status=1; \
	$(MAKE) clean-sonarqube-data || status=1; \
	exit $$status

# Prepare all test data: run GitLab, Nexus, Harbor, and SonarQube data preparation in order
# Required environment variables:
# - GITLAB_URL, GITLAB_TOKEN (for GitLab)
# - NEXUS_URL, NEXUS_USERNAME, NEXUS_PASSWORD (for Nexus)
# - HARBOR_URL, HARBOR_HOST, HARBOR_PORT, HARBOR_SCHEME, HARBOR_USERNAME, HARBOR_PASSWORD (for Harbor)
# - SONARQUBE_URL, SONARQUBE_MANAGER_TOKEN (for SonarQube)
.PHONY: prepare-all-data
prepare-all-data: prepare-gitlab-data prepare-nexus-data prepare-harbor-data prepare-sonarqube-data
	@echo "========================================="
	@echo "All test data preparation completed!"
	@echo "========================================="
	@echo "GitLab config: $(GENERATED_GITLAB_USERS_FILE)"
	@echo "Nexus config: $(GENERATED_NEXUS_USERS_FILE)"
	@echo "Harbor config: $(HARBOR_GENERATED_FILE)"
	@echo "SonarQube config: $(GENERATED_SONARQUBE_USERS_FILE)"
	@echo "========================================="
	@$(MAKE) show-config

.PHONY: show-config
show-config:
	@echo "Current Testing Configuration ($(TESTING_CONFIG)):"
	@cat $(TESTING_CONFIG)
	@echo "========================================="

# go-install-tool will 'go install' any package with custom target and name of binary, if it doesn't exist
# $1 - target path with name of binary (ideally with version)
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@{ \
set -e; \
$(call executable-artifact-check-fn) \
if [ -f "$(1)" ] && ! is_executable_artifact "$(1)"; then \
	echo "Existing tool at $(1) is not executable, removing it..."; \
	rm -f "$(1)"; \
fi; \
[ -f "$(1)" ] || { \
	package=$(2)@$(3) ;\
	echo "Downloading $${package} into $(TOOLBIN) as $(1)" ;\
	GOBIN=$(TOOLBIN) go install $${package} ;\
	mv "$$(echo "$(1)" | sed "s/-$(3)$$//")" "$(1)" ;\
	if ! is_executable_artifact "$(1)"; then \
		echo "Error: Installed tool at $(1) is not executable"; \
		rm -f "$(1)"; \
		exit 1; \
	fi; \
}; \
}
endef

# download-file will download file from url and save to target path
# $1 - url to download the file
# $2 - target path to save the file
define download-file
@{ \
set -e; \
echo "Downloading file from $(1) into $(2)" ;\
curl --retry 6 -sSL $(1) --create-dirs -o $(2) ;\
}
endef

%: %-default
	@ true
