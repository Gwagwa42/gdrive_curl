# Makefile for gdrive_curl.sh

# Variables
SCRIPT = gdrive_curl.sh
TEST_DIR = tests
INSTALL_DIR = /usr/local/bin
SCRIPT_NAME = gdrive-curl

# Default target
.PHONY: help
help:
	@echo "gdrive_curl.sh Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make test          - Run all tests"
	@echo "  make test-auth     - Run authentication tests"
	@echo "  make test-file     - Run file operations tests"
	@echo "  make test-folder   - Run folder operations tests"
	@echo "  make test-perms    - Run permission tests"
	@echo "  make test-star     - Run star/trash tests"
	@echo "  make test-search   - Run search/export tests"
	@echo "  make test-revisions - Run version history tests"
	@echo "  make test-verbose  - Run all tests with verbose output"
	@echo "  make test-quick    - Run quick tests only"
	@echo "  make install       - Install script to $(INSTALL_DIR)"
	@echo "  make uninstall     - Remove script from $(INSTALL_DIR)"
	@echo "  make check         - Check syntax with shellcheck"
	@echo "  make clean         - Clean test logs and data"
	@echo "  make auth          - Authenticate with Google Drive"

# Test targets
.PHONY: test
test:
	@cd $(TEST_DIR) && ./run_tests.sh

.PHONY: test-auth
test-auth:
	@cd $(TEST_DIR) && ./run_tests.sh auth

.PHONY: test-file
test-file:
	@cd $(TEST_DIR) && ./run_tests.sh file

.PHONY: test-folder
test-folder:
	@cd $(TEST_DIR) && ./run_tests.sh folder

.PHONY: test-perms
test-perms:
	@cd $(TEST_DIR) && ./run_tests.sh permissions

.PHONY: test-star
test-star:
	@cd $(TEST_DIR) && ./run_tests.sh star-trash

.PHONY: test-search
test-search:
	@cd $(TEST_DIR) && ./run_tests.sh search-export

.PHONY: test-revisions
test-revisions:
	@cd $(TEST_DIR) && ./run_tests.sh revisions

.PHONY: test-verbose
test-verbose:
	@cd $(TEST_DIR) && ./run_tests.sh -v

.PHONY: test-quick
test-quick:
	@cd $(TEST_DIR) && QUICK=1 ./run_tests.sh

.PHONY: test-no-cleanup
test-no-cleanup:
	@cd $(TEST_DIR) && ./run_tests.sh -n

# Installation targets
.PHONY: install
install:
	@echo "Installing $(SCRIPT) to $(INSTALL_DIR)/$(SCRIPT_NAME)"
	@sudo cp $(SCRIPT) $(INSTALL_DIR)/$(SCRIPT_NAME)
	@sudo chmod +x $(INSTALL_DIR)/$(SCRIPT_NAME)
	@echo "Installation complete. You can now use: $(SCRIPT_NAME)"

.PHONY: uninstall
uninstall:
	@echo "Removing $(SCRIPT_NAME) from $(INSTALL_DIR)"
	@sudo rm -f $(INSTALL_DIR)/$(SCRIPT_NAME)
	@echo "Uninstall complete"

# Development targets
.PHONY: check
check:
	@echo "Checking shell script syntax..."
	@bash -n $(SCRIPT)
	@echo "✓ Syntax check passed"
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck..."; \
		shellcheck -e SC2086,SC2181 $(SCRIPT); \
		echo "✓ Shellcheck passed"; \
	else \
		echo "ℹ shellcheck not installed, skipping"; \
	fi

.PHONY: clean
clean:
	@echo "Cleaning test logs and data..."
	@rm -rf $(TEST_DIR)/logs/*
	@rm -rf $(TEST_DIR)/data/*
	@echo "✓ Clean complete"

.PHONY: auth
auth:
	@./$(SCRIPT) init

# Statistics
.PHONY: stats
stats:
	@echo "gdrive_curl.sh Statistics:"
	@echo "=========================="
	@echo "Total lines: $$(wc -l < $(SCRIPT))"
	@echo "Total commands: $$(grep -c '^\s\+[a-z-]\+)' $(SCRIPT) || echo 0)"
	@echo "Functions: $$(grep -c '^[a-z_]\+()' $(SCRIPT))"
	@echo "Test files: $$(ls -1 $(TEST_DIR)/test_*.sh 2>/dev/null | wc -l)"
	@echo ""
	@echo "Commands:"
	@grep '^\s\+[a-z-]\+)' $(SCRIPT) | sed 's/)//' | awk '{print "  - " $$1}' | sort | uniq

# Documentation
.PHONY: docs
docs:
	@echo "Generating command list..."
	@./$(SCRIPT) --help

.DEFAULT_GOAL := help