BEAT_NAME=deepbeats
BEAT_PATH=github.com/DeepInThought/deepbeats
BEAT_GOPATH=$(firstword $(subst :, ,${GOPATH}))
SYSTEM_TESTS=true
TEST_ENVIRONMENT=true
ES_BEATS?=./vendor/github.com/elastic/beats
GOPACKAGES=$(shell govendor list -no-status +local)
GOBUILD_FLAGS=-i -ldflags "-X $(BEAT_PATH)/vendor/github.com/DeepInThought/deepbeats/version.buildTime=$(NOW) -X $(BEAT_PATH)/vendor/github.com/DeepInThought/deepbeats/version.commit=$(COMMIT_ID)"
MAGE_IMPORT_PATH=${BEAT_PATH}/vendor/github.com/magefile/mage
BUILD_DIR=$(CURDIR)/build
COVERAGE_DIR=$(BUILD_DIR)/coverage
BEATS?=auditbeat filebeat heartbeat metricbeat packetbeat winlogbeat
PROJECTS=$(BEAT_GOPATH)/src/$(BEAT_PATH)/vendor/
PROJECTS_ENV=$(BEAT_NAME)
PYTHON_ENV?=$(BUILD_DIR)/python-env/activate
VIRTUALENV_PARAMS?=
FIND=find . -type f -not -path "*/vendor/*" -not -path "*/build/*" -not -path "*/.git/*"
GOLINT=golint
GOLINT_REPO=github.com/golang/lint/golint
REVIEWDOG=reviewdog
REVIEWDOG_OPTIONS?=-diff "git diff master"
REVIEWDOG_REPO=github.com/haya14busa/reviewdog/cmd/reviewdog

# Path to the libbeat Makefile
-include $(ES_BEATS)/libbeat/scripts/Makefile

# Initial beat setup
.PHONY: deep-setup
deep-setup: copy-vendor git-init deep-update git-add

# Copy beats into vendor directory
.PHONY: copy-vendor
copy-vendor:
	mkdir -p vendor/github.com/elastic
	cp -R ${BEAT_GOPATH}/src/github.com/elastic/beats vendor/github.com/elastic/
	rm -rf vendor/github.com/elastic/beats/.git vendor/github.com/elastic/beats/x-pack
	mkdir -p vendor/github.com/magefile
	cp -R ${BEAT_GOPATH}/src/github.com/elastic/beats/vendor/github.com/magefile/mage vendor/github.com/magefile

.PHONY: git-init
git-init:
	git init

.PHONY: git-add
git-add:
	git add -A
	git commit -m "Add generated deepbeats files"

.PHONY: deep-testsuites
deep-testsuites:
	@$(foreach var,$(PROJECTS),$(MAKE) -C $(var) deep-testsuites || exit 1;)

# Runs complete testsuites (unit, system, integration) for all beats with coverage and race detection.
# Also it builds the docs and the generators

.PHONY: setup-commit-hook
setup-commit-hook:
	@cp script/pre_commit.sh .git/hooks/pre-commit
	@chmod 751 .git/hooks/pre-commit

.PHONY: deep-coverage-report
deep-coverage-report:
	@mkdir -p $(COVERAGE_DIR)
	@echo 'mode: atomic' > ./$(COVERAGE_DIR)/full.cov
	@# Collects all coverage files and skips top line with mode
	@$(foreach var,$(PROJECTS),tail -q -n +2 ./$(var)/$(COVERAGE_DIR)/*.cov >> ./$(COVERAGE_DIR)/full.cov || true;)
	@go tool cover -html=./$(COVERAGE_DIR)/full.cov -o $(COVERAGE_DIR)/full.html
	@echo "Generated coverage report $(COVERAGE_DIR)/full.html"

.PHONY: deep-update
deep-deep-update: deep-notice
	@$(foreach var,$(PROJECTS),$(MAKE) -C $(var) deep-update || exit 1;)
	@$(MAKE) -C deploy/kubernetes all

.PHONY: deep-fmt
deep-fmt: add-headers python-env
	@$(foreach var,$(PROJECTS) dev-tools,$(MAKE) -C $(var) deep-fmtt || exit 1;)
	@# Cleans also python files which are not part of the beats
	@$(FIND) -name "*.py" -exec $(PYTHON_ENV)/bin/autopep8 --in-place --max-line-length 120 {} \;

stop-environments:
	@$(foreach var,$(PROJECTS_ENV),$(MAKE) -C $(var) stop-environment || exit 0;)

# Cleans up the vendor directory from unnecessary files
# This should always be run after updating the dependencies
.PHONY: deep-clean-vendor
deep-clean-vendor:
	@sh script/clean_vendor.sh

# Corrects spelling errors
.PHONY: misspell
misspell:
	go get -u github.com/client9/misspell/cmd/misspell
	# Ignore Kibana files (.json)
	$(FIND) \
		-not -path "*.json" \
		-not -path "*.log" \
		-name '*' \
		-exec misspell -w {} \;

.PHONY: deep-notice
deep-notice: deep-python-env
	@echo "Generating NOTICE"
	@$(PYTHON_ENV)/bin/python dev-tools/generate_notice.py .

# Sets up the virtual python environment
.PHONY: deep-python-env
deep-python-env:
	@test -d $(PYTHON_ENV) || virtualenv $(VIRTUALENV_PARAMS) $(PYTHON_ENV)
	@$(PYTHON_ENV)/bin/pip install -q --upgrade pip autopep8 six
	@# Work around pip bug. See: https://github.com/pypa/pip/issues/4464
	@find $(PYTHON_ENV) -type d -name dist-packages -exec sh -c "echo dist-packages > {}.pth" ';'

# Tests if apm works with the current code
.PHONY: deep-test-apm
deep-test-apm:
	sh ./script/test_apm.sh

### Packaging targets ####

# Builds a snapshot release.
.PHONY: deep-snapshot
deep-snapshot:
	@$(MAKE) SNAPSHOT=true deep-release

# Builds a release.
.PHONY: deep-release
deep-release: deep-beats-dashboards
	@$(foreach var,$(ES_BEATS),$(MAKE) -C $(var) release || exit 1;)
	@$(foreach var,$(ES_BEATS), \
      test -d $(var)/build/distributions && test -n "$$(ls $(var)/build/distributions)" || exit 0; \
      mkdir -p build/distributions/$(var) && mv -f $(var)/build/distributions/* build/distributions/$(var)/ || exit 1;)

# Builds a snapshot release. The Go version defined in .go-version will be
# installed and used for the build.
.PHONY: deep-release-manager-snapshot
deep-release-manager-snapshot:
	@$(MAKE) SNAPSHOT=true deep-release-manager-release

# Builds a snapshot release. The Go version defined in .go-version will be
# installed and used for the build.
.PHONY: deep-release-manager-release
deep-release-manager-release:
	./dev-tools/run_with_go_ver $(MAKE) deep-release

# Installs the mage build tool from the vendor directory.
.PHONY: mage
mage:
	@go install github.com/elastic/beats/vendor/github.com/magefile/mage

# Collects dashboards from all Beats and generates a zip file distribution.
.PHONY: deep-beats-dashboards
deep-beats-dashboards: mage deep-update
	@mage packageBeatDashboards
