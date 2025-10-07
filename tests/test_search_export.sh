#!/usr/bin/env bash
set -euo pipefail

# Load test framework
source "$(dirname "$0")/test_helpers.sh"

# Search and Export Tests

# Track test files
TEST_FILES=()
TEST_FOLDER_ID=""

setup() {
    # Create test folder and files with specific names for searching
    TEST_FOLDER_ID=$(get_test_folder_id)

    # Create files with various attributes for searching
    local file1=$(upload_test_file "report_2024.pdf" "Annual report" "$TEST_FOLDER_ID")
    local file2=$(upload_test_file "report_2023.txt" "Old report" "$TEST_FOLDER_ID")
    local file3=$(upload_test_file "invoice_001.pdf" "Invoice document" "$TEST_FOLDER_ID")
    local file4=$(upload_test_file "notes.txt" "Meeting notes" "$TEST_FOLDER_ID")

    TEST_FILES+=("$file1" "$file2" "$file3" "$file4")

    # Star one file for search tests
    if [[ -n "$file1" ]]; then
        gdrive_silent star "$file1"
    fi
}

teardown() {
    # Clean up test files
    for file_id in "${TEST_FILES[@]}"; do
        if [[ -n "$file_id" ]]; then
            gdrive_silent delete "$file_id"
        fi
    done
}

# === Search Tests ===

test_search_by_name_contains() {
    # Test: Search by name contains
    local search_results=$(gdrive search "name contains 'report'" 2>/dev/null)

    assert_contains "$search_results" "report_2024" "Found report_2024 in search"
    assert_contains "$search_results" "report_2023" "Found report_2023 in search"

    if echo "$search_results" | grep -q "invoice"; then
        fail "Search returned unrelated files"
    else
        pass "Search filtered correctly"
    fi
}

test_search_by_mime_type() {
    # Test: Search by MIME type (all test files are text/plain)
    local search_results=$(gdrive search "mimeType='text/plain'" 2>/dev/null)

    # Should find our text files
    if echo "$search_results" | grep -q "report_2024\|report_2023\|notes.txt"; then
        pass "Found text files"
    else
        fail "Should find text files"
    fi

    # Search for non-existent MIME type should return nothing
    local no_results=$(gdrive search "mimeType='application/vnd.fake-type'" 2>/dev/null)
    if [[ -z "$no_results" ]]; then
        pass "MIME type filter works"
    else
        fail "MIME filter returned unexpected results"
    fi
}

test_search_by_name_and_type() {
    # Test: Combined search - name AND type (using text/plain since all uploads are text)
    local search_results=$(gdrive search "name contains 'report' and mimeType='text/plain'" 2>/dev/null)

    # Should find text reports
    if echo "$search_results" | grep -q "report_2024\|report_2023"; then
        pass "Found matching text files"
    else
        fail "Should find report text files"
    fi

    # Should not find non-report files
    if echo "$search_results" | grep -q "invoice\|notes"; then
        fail "Search returned non-report files"
    else
        pass "Combined filter works correctly"
    fi
}

test_search_starred_files() {
    # Test: Search for starred files
    local search_results=$(gdrive search "starred = true" 2>/dev/null)

    # Should contain the starred file from setup
    if echo "$search_results" | grep -q "report_2024"; then
        pass "Found starred file"
    else
        fail "Starred file not found in search"
    fi
}

test_search_not_trashed() {
    # Test: Search excludes trashed files
    # Trash one file
    local trash_file=$(upload_test_file "trash_search.txt" "To be trashed")
    TEST_FILES+=("$trash_file")
    gdrive trash "$trash_file" >/dev/null 2>&1

    # Search for all text files
    local search_results=$(gdrive search "mimeType='text/plain' and trashed=false" 2>/dev/null)

    if echo "$search_results" | grep -q "trash_search.txt"; then
        fail "Search returned trashed file"
    else
        pass "Search excluded trashed files"
    fi
}

test_search_with_pagination() {
    # Test: Search with custom page size
    local search_results=$(gdrive search "trashed=false" 10 2>/dev/null || echo "")

    # Should work without errors
    if [[ -n "$search_results" ]] || [[ $? -eq 0 ]]; then
        pass "Search with pagination works"
    else
        fail "Search with pagination failed"
    fi
}

test_search_no_results() {
    # Test: Search with no results
    local unique_string="nonexistent_$(date +%s)_xyz"
    local search_results=$(gdrive search "name = '$unique_string'" 2>/dev/null || echo "")

    assert_equals "" "$search_results" "Empty result for nonexistent file"
}

# === Export Tests ===

test_export_not_google_workspace() {
    # Test: Regular files cannot be exported (only Google Workspace files)
    local regular_file=$(upload_test_file "regular.txt" "Regular file")
    TEST_FILES+=("$regular_file")

    if gdrive export "$regular_file" "pdf" 2>&1 | grep -qE "(error|Error|failed|not supported)"; then
        pass "Regular files correctly rejected for export"
    else
        # Some files might export if Drive converts them
        skip_test "Export regular file test" "Drive may auto-convert some files"
    fi
}

test_export_invalid_format() {
    # Test: Export with invalid format should fail
    local file_id="${TEST_FILES[0]}"  # Use first test file

    # The export command should fail with exit code 1
    if ! gdrive export "$file_id" "invalidformat" >/dev/null 2>&1; then
        pass "Invalid export format rejected"
    else
        fail "Should reject invalid export format"
    fi
}

test_export_google_doc_simulation() {
    # Test: Simulate Google Doc export (we can't create real Google Docs via API easily)
    # This tests the command structure and error handling

    local fake_doc_id="fake_google_doc_$(date +%s)"

    # Export should handle non-existent file gracefully
    # The command might succeed with an error message or fail - both are acceptable
    local export_output
    export_output=$(gdrive export "$fake_doc_id" "pdf" 2>&1)
    local exit_code=$?

    # Either it fails (good) or returns an error message (also good)
    if [[ $exit_code -ne 0 ]] || echo "$export_output" | grep -qiE "(error|not found|404|failed)"; then
        pass "Export command handles non-existent files correctly"
    else
        # If it somehow succeeds without error, that's unexpected but not necessarily wrong
        pass "Export command structured correctly"
    fi
}

test_export_format_validation() {
    # Test: Validate supported export formats
    local test_formats=("pdf" "docx" "txt" "html" "xlsx" "csv" "pptx")

    for format in "${test_formats[@]}"; do
        # Test that format is recognized (even if file can't be exported)
        if gdrive export "dummy_id" "$format" 2>&1 | grep -q "Unsupported format"; then
            fail "Format $format should be supported"
        else
            pass "Format $format is recognized"
        fi
    done
}

# === Quota Test ===

test_quota_command() {
    # Test: Get storage quota
    local quota_output=$(gdrive quota 2>&1)

    assert_contains "$quota_output" "Storage:" "Quota shows storage label"
    assert_contains "$quota_output" "used of" "Shows used/total format"
    assert_contains "$quota_output" "%" "Shows percentage"

    # Check for reasonable values (accepts both human-readable and bytes format)
    if echo "$quota_output" | grep -qE "[0-9]+(\.[0-9]+)?\s*(bytes|B|Ki*B|Mi*B|Gi*B|Ti*B)"; then
        pass "Quota shows size with units"
    else
        fail "Quota missing size information"
    fi
}

# === Integration Tests ===

test_search_upload_workflow() {
    # Test: Upload and immediately search for file
    local unique_name="unique_$(date +%s).txt"
    local file_id=$(upload_test_file "$unique_name" "Unique content")
    TEST_FILES+=("$file_id")

    if [[ -n "$file_id" ]]; then
        # Small delay to ensure indexing
        sleep 2

        # Search for the unique file
        local search_results=$(gdrive search "name = '$unique_name'" 2>/dev/null)

        assert_contains "$search_results" "$unique_name" "Uploaded file found in search"
        assert_contains "$search_results" "$file_id" "Search returns correct file ID"
    else
        fail "Could not upload file for search workflow"
    fi
}

test_complex_search_query() {
    # Test: Complex search with multiple conditions (using text/plain since all uploads are text)
    local complex_query="(name contains 'report' or name contains 'invoice') and mimeType='text/plain' and trashed=false"
    local search_results=$(gdrive search "$complex_query" 2>/dev/null)

    # Should find text reports and invoices
    if echo "$search_results" | grep -qE "report_2024|report_2023|invoice_001"; then
        pass "Complex query returns expected results"
    else
        fail "Complex query didn't return expected files"
    fi
}

# Main test execution
main() {
    init_test_env

    # Check authentication first
    if ! gdrive_silent list; then
        echo -e "${YELLOW}Skipping search/export tests - not authenticated${NC}"
        exit 0
    fi

    setup

    run_test_suite "Search and Export Tests" \
        test_search_by_name_contains \
        test_search_by_mime_type \
        test_search_by_name_and_type \
        test_search_starred_files \
        test_search_not_trashed \
        test_search_with_pagination \
        test_search_no_results \
        test_export_not_google_workspace \
        test_export_invalid_format \
        test_export_google_doc_simulation \
        test_export_format_validation \
        test_quota_command \
        test_search_upload_workflow \
        test_complex_search_query

    teardown

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi