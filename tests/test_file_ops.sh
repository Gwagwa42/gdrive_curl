#!/usr/bin/env bash
set -euo pipefail

# Load test framework
source "$(dirname "$0")/test_helpers.sh"

# File Operations Tests

# Global test file tracking
TEST_FILES=()
TEST_FOLDER_ID=""

setup() {
    # Create test folder for this suite
    TEST_FOLDER_ID=$(get_test_folder_id)
    assert_not_empty "$TEST_FOLDER_ID" "Test folder created"
}

teardown() {
    # Clean up test files
    for file_id in "${TEST_FILES[@]}"; do
        cleanup_test_file "$file_id"
    done
}

test_upload_small_file() {
    # Test: Upload a small file
    local test_file=$(create_test_file "small.txt" "Small file content")
    local upload_output=$(gdrive upload "$test_file")
    local file_id=$(echo "$upload_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$file_id" "File uploaded successfully"; then
        TEST_FILES+=("$file_id")

        # Verify file exists
        local file_info=$(gdrive info "$file_id" 2>/dev/null)
        assert_contains "$file_info" "small.txt" "Uploaded file has correct name"
    fi
}

test_upload_with_custom_name() {
    # Test: Upload file with custom name
    local test_file=$(create_test_file "original.txt" "Content")
    local custom_name="renamed_file.txt"
    local upload_output=$(gdrive upload "$test_file" "$custom_name")
    local file_id=$(echo "$upload_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$file_id" "File uploaded with custom name"; then
        TEST_FILES+=("$file_id")

        local file_info=$(gdrive info "$file_id" 2>/dev/null)
        assert_contains "$file_info" "$custom_name" "File has custom name"
    fi
}

test_upload_to_folder() {
    # Test: Upload file to specific folder
    local test_file=$(create_test_file "folder_test.txt" "In folder")
    local upload_output=$(gdrive upload "$test_file" "folder_test.txt" "$TEST_FOLDER_ID")
    local file_id=$(echo "$upload_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$file_id" "File uploaded to folder"; then
        TEST_FILES+=("$file_id")

        # Verify file is in folder
        local files_in_folder=$(gdrive list "$TEST_FOLDER_ID" 2>/dev/null)
        assert_contains "$files_in_folder" "folder_test.txt" "File is in correct folder"
    fi
}

test_download_file() {
    # Test: Download a file
    local file_id=$(upload_test_file "download_test.txt" "Download me!")

    if [[ -n "$file_id" ]]; then
        TEST_FILES+=("$file_id")

        local download_path="$TEST_DATA_DIR/downloaded_$(date +%s).txt"
        gdrive download "$file_id" "$download_path"

        assert_file_exists "$download_path" "File downloaded successfully"

        if [[ -f "$download_path" ]]; then
            local content=$(cat "$download_path")
            assert_equals "Download me!" "$content" "Downloaded content matches"
        fi
    else
        fail "Could not create file for download test"
    fi
}

test_download_auto_filename() {
    # Test: Download file with auto-detected filename
    local file_id=$(upload_test_file "auto_name.txt" "Auto filename test")

    if [[ -n "$file_id" ]]; then
        TEST_FILES+=("$file_id")

        cd "$TEST_DATA_DIR"
        gdrive download "$file_id"

        assert_file_exists "auto_name.txt" "File downloaded with auto-detected name"
        cd - > /dev/null
    else
        fail "Could not create file for auto-filename test"
    fi
}

test_update_file_content() {
    # Test: Update existing file content
    local file_id=$(upload_test_file "update_test.txt" "Original content")

    if [[ -n "$file_id" ]]; then
        TEST_FILES+=("$file_id")

        # Create new content
        local new_file=$(create_test_file "new_content.txt" "Updated content!")
        gdrive update "$file_id" "$new_file"

        # Download and verify
        local verify_path="$TEST_DATA_DIR/verify_update.txt"
        gdrive download "$file_id" "$verify_path"

        if [[ -f "$verify_path" ]]; then
            local content=$(cat "$verify_path")
            assert_equals "Updated content!" "$content" "File content updated"
        fi
    else
        fail "Could not create file for update test"
    fi
}

test_copy_file() {
    # Test: Copy a file
    local file_id=$(upload_test_file "original.txt" "Copy me")

    if [[ -n "$file_id" ]]; then
        TEST_FILES+=("$file_id")

        local copy_output=$(gdrive copy "$file_id" "copied_file.txt")
        local copy_id=$(echo "$copy_output" | jq -r '.id' 2>/dev/null || echo "")

        if assert_not_empty "$copy_id" "File copied successfully"; then
            TEST_FILES+=("$copy_id")

            local copy_info=$(gdrive info "$copy_id" 2>/dev/null)
            assert_contains "$copy_info" "copied_file.txt" "Copy has correct name"
        fi
    else
        fail "Could not create file for copy test"
    fi
}

test_rename_file() {
    # Test: Rename a file
    local file_id=$(upload_test_file "old_name.txt" "Rename me")

    if [[ -n "$file_id" ]]; then
        TEST_FILES+=("$file_id")

        gdrive rename "$file_id" "new_name.txt"

        local file_info=$(gdrive info "$file_id" 2>/dev/null)
        assert_contains "$file_info" "new_name.txt" "File renamed successfully"
    else
        fail "Could not create file for rename test"
    fi
}

test_move_file() {
    # Test: Move file to different folder
    local file_id=$(upload_test_file "moveme.txt" "Move me to folder")

    if [[ -n "$file_id" ]] && [[ -n "$TEST_FOLDER_ID" ]]; then
        TEST_FILES+=("$file_id")

        gdrive move "$file_id" "$TEST_FOLDER_ID"

        # Verify file is in new folder
        local files_in_folder=$(gdrive list "$TEST_FOLDER_ID" 2>/dev/null)
        assert_contains "$files_in_folder" "moveme.txt" "File moved to folder"
    else
        fail "Could not create file or folder for move test"
    fi
}

test_file_info() {
    # Test: Get file information
    local file_id=$(upload_test_file "info_test.txt" "Get my info")

    if [[ -n "$file_id" ]]; then
        TEST_FILES+=("$file_id")

        local file_info=$(gdrive info "$file_id")

        assert_contains "$file_info" "info_test.txt" "Info contains filename"
        assert_contains "$file_info" "text/plain" "Info contains MIME type"
        assert_contains "$file_info" '"id"' "Info contains file ID"
    else
        fail "Could not create file for info test"
    fi
}

test_list_files() {
    # Test: List files
    # Upload a few test files
    local file1=$(upload_test_file "list1.txt" "File 1" "$TEST_FOLDER_ID")
    local file2=$(upload_test_file "list2.txt" "File 2" "$TEST_FOLDER_ID")
    local file3=$(upload_test_file "list3.txt" "File 3" "$TEST_FOLDER_ID")

    TEST_FILES+=("$file1" "$file2" "$file3")

    local list_output=$(gdrive list "$TEST_FOLDER_ID")

    assert_contains "$list_output" "list1.txt" "List contains file 1"
    assert_contains "$list_output" "list2.txt" "List contains file 2"
    assert_contains "$list_output" "list3.txt" "List contains file 3"
}

test_upload_large_file() {
    # Test: Upload a large file (using resumable upload)
    # Create a 6MB file
    local large_file="$TEST_DATA_DIR/large_file.bin"
    dd if=/dev/zero of="$large_file" bs=1M count=6 2>/dev/null

    local upload_output=$(gdrive upload-big "$large_file" "large_test.bin")
    local file_id=$(echo "$upload_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$file_id" "Large file uploaded successfully"; then
        TEST_FILES+=("$file_id")

        local file_info=$(gdrive info "$file_id" 2>/dev/null)
        assert_contains "$file_info" "large_test.bin" "Large file has correct name"
    fi
}

# Main test execution
main() {
    init_test_env

    # Check authentication first
    if ! gdrive_silent list; then
        echo -e "${YELLOW}Skipping file operations tests - not authenticated${NC}"
        exit 0
    fi

    setup

    run_test_suite "File Operations Tests" \
        test_upload_small_file \
        test_upload_with_custom_name \
        test_upload_to_folder \
        test_download_file \
        test_download_auto_filename \
        test_update_file_content \
        test_copy_file \
        test_rename_file \
        test_move_file \
        test_file_info \
        test_list_files \
        test_upload_large_file

    teardown

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi