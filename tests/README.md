# gdrive_curl.sh Test Suite

Comprehensive test suite for gdrive_curl.sh covering all 29 commands and major functionality, including OAuth scope management.

## Quick Start

```bash
# Run all tests (default: app-only mode)
./run_tests.sh

# Run tests with different OAuth scopes
SCOPE_MODE=app ./run_tests.sh    # App-only access (drive.file scope)
SCOPE_MODE=full ./run_tests.sh   # Full Drive access (drive scope)

# Run specific test suite
./run_tests.sh auth
./run_tests.sh scope
./run_tests.sh file
./run_tests.sh permissions

# Run with verbose output
./run_tests.sh -v

# Run without cleanup (keep test files for debugging)
./run_tests.sh -n

# List available test suites
./run_tests.sh -l
```

## OAuth Scope Testing

The test suite supports testing with two different OAuth scopes:

- **App-only mode** (`drive.file`): Default mode, only accesses files created by the app
- **Full access mode** (`drive`): Full Google Drive access for comprehensive testing

### Running Tests with Different Scopes

```bash
# Using environment variables
SCOPE_MODE=app make test     # Test with app-only scope
SCOPE_MODE=full make test    # Test with full Drive scope

# Using Makefile targets
make test-app               # Run all tests with app-only scope
make test-full              # Run all tests with full Drive scope
make test-all               # Run tests with both scopes

# Test specific suite with scope
SCOPE_MODE=full ./run_tests.sh file
```

## Test Coverage

### Test Suites

1. **Authentication Tests** (`test_auth.sh`)
   - Token validation
   - Authentication status
   - Token file integrity
   - Basic command access
   - Scope command functionality

2. **OAuth Scope Tests** (`test_scope.sh`)
   - Scope command output
   - --app-only and --full-access flags
   - SCOPE_MODE environment variable
   - Token file separation
   - Flag vs environment precedence
   - Default scope mode validation

3. **File Operations Tests** (`test_file_ops.sh`)
   - Upload (small and large files)
   - Download (with and without filename)
   - Update file content
   - Copy, rename, move files
   - File information retrieval
   - List files with pagination

3. **Folder Operations Tests** (`test_folder_ops.sh`)
   - Create folders and nested folders
   - Find folders by name
   - List folder contents
   - Rename and move folders
   - Delete empty folders

4. **Permission Management Tests** (`test_permissions.sh`)
   - Share files with different roles
   - List file permissions
   - Update permission roles
   - Delete permissions
   - Complete permission workflow

5. **Star and Trash Tests** (`test_star_trash.sh`)
   - Star and unstar files
   - List starred files
   - Move files to trash
   - List trash contents
   - Restore from trash
   - Permanent deletion

6. **Search and Export Tests** (`test_search_export.sh`)
   - Search by name, MIME type, and status
   - Complex search queries
   - Export format validation
   - Storage quota checking

7. **Version History Tests** (`test_revisions.sh`)
   - List file revisions
   - Download specific revisions
   - Verify revision metadata
   - Handle files without revisions

## Prerequisites

1. **Authentication Required**
   ```bash
   # Authenticate with app-only scope (default)
   ../gdrive_curl.sh --app-only init

   # Or authenticate with full Drive access
   ../gdrive_curl.sh --full-access init

   # Note: Different scopes use different token files
   # App-only: ~/.config/gdrive-curl/tokens-app.json
   # Full access: ~/.config/gdrive-curl/tokens-full.json
   ```

2. **Dependencies**
   - bash 4.0+
   - curl
   - jq
   - Google Drive API access

## Test Framework Features

### Helper Functions

The test framework (`test_helpers.sh`) provides:

- **Assertions**: `assert_equals`, `assert_contains`, `assert_not_empty`, `assert_file_exists`
- **Test Management**: `run_test`, `skip_test`, `pass`, `fail`
- **Drive Helpers**: `upload_test_file`, `get_test_folder_id`, `cleanup_test_file`
- **Logging**: All tests log to `logs/` directory
- **Cleanup**: Automatic cleanup of test files (can be disabled)

### Environment Variables

```bash
# Disable cleanup (keep test files for debugging)
export TEST_CLEANUP=0

# Enable verbose output
export VERBOSE=1

# Skip slow tests
export QUICK=1
```

## Running Individual Test Suites

Each test suite can be run independently:

```bash
# Run authentication tests only
./test_auth.sh

# Run file operations tests
./test_file_ops.sh

# Run permission tests
./test_permissions.sh
```

## Test Output

Tests provide colored output for easy reading:
- 🟢 **GREEN**: Passed tests
- 🔴 **RED**: Failed tests
- 🟡 **YELLOW**: Skipped tests
- 🔵 **BLUE**: Test information

## Logs

All test runs generate logs in the `logs/` directory:
- Individual test suite logs: `test_auth_20240115_143022.log`
- Summary logs: `test_summary_20240115_143022.log`

## Writing New Tests

To add a new test:

1. Create a test function:
```bash
test_my_feature() {
    # Test: Description
    local result=$(gdrive my-command)
    assert_contains "$result" "expected" "My feature works"
}
```

2. Add to test suite:
```bash
run_test_suite "My Tests" \
    test_my_feature \
    test_another_feature
```

## Troubleshooting

### Tests Fail with Authentication Error
```bash
# Re-authenticate
../gdrive_curl.sh init
```

### Tests Leave Files in Google Drive
```bash
# Manual cleanup
../gdrive_curl.sh list | grep "test_file" | awk '{print $1}' | \
    xargs -I {} ../gdrive_curl.sh delete {}
```

### View Detailed Test Logs
```bash
# Check latest log
ls -la logs/ | tail -1
cat logs/test_auth_*.log
```

## CI/CD Integration

The test suite returns appropriate exit codes:
- `0`: All tests passed
- `1`: One or more tests failed

Example GitHub Actions workflow:
```yaml
- name: Run gdrive_curl tests
  run: |
    cd tests
    ./run_tests.sh
```

## Coverage Report

The test suite covers:
- ✅ All 28 commands
- ✅ Authentication flows
- ✅ Error handling
- ✅ Edge cases
- ✅ Pagination
- ✅ Permission management
- ✅ File operations
- ✅ Search queries
- ✅ Trash operations
- ✅ Star management

## Contributing

When adding new features to gdrive_curl.sh:
1. Add corresponding tests
2. Update this README
3. Run full test suite before committing
4. Check test logs for any warnings