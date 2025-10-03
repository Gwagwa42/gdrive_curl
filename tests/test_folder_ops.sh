#!/usr/bin/env bash
set -euo pipefail

# Load test framework
source "$(dirname "$0")/test_helpers.sh"

# Folder Operations Tests

# Track created folders for cleanup
TEST_FOLDERS=()

teardown() {
    # Clean up test folders
    for folder_id in "${TEST_FOLDERS[@]}"; do
        if [[ -n "$folder_id" ]]; then
            gdrive_silent delete "$folder_id"
        fi
    done
}

test_create_folder() {
    # Test: Create a folder
    local folder_name="test_folder_$(date +%s)"
    local create_output=$(gdrive create-folder "$folder_name")
    local folder_id=$(echo "$create_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$folder_id" "Folder created successfully"; then
        TEST_FOLDERS+=("$folder_id")

        local folder_info=$(gdrive info "$folder_id" 2>/dev/null)
        assert_contains "$folder_info" "$folder_name" "Folder has correct name"
        assert_contains "$folder_info" "application/vnd.google-apps.folder" "Has folder MIME type"
    fi
}

test_create_nested_folder() {
    # Test: Create a folder inside another folder
    local parent_name="parent_folder_$(date +%s)"
    local child_name="child_folder_$(date +%s)"

    # Create parent folder
    local parent_output=$(gdrive create-folder "$parent_name")
    local parent_id=$(echo "$parent_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$parent_id" "Parent folder created"; then
        TEST_FOLDERS+=("$parent_id")

        # Create child folder
        local child_output=$(gdrive create-folder "$child_name" "$parent_id")
        local child_id=$(echo "$child_output" | jq -r '.id' 2>/dev/null || echo "")

        if assert_not_empty "$child_id" "Child folder created"; then
            TEST_FOLDERS+=("$child_id")

            # Verify child is in parent
            local files_in_parent=$(gdrive list "$parent_id" 2>/dev/null)
            assert_contains "$files_in_parent" "$child_name" "Child folder is in parent"
        fi
    fi
}

test_find_folder_by_name() {
    # Test: Find folder by name
    local unique_name="unique_folder_$(date +%s)"

    # Create a folder with unique name
    local create_output=$(gdrive create-folder "$unique_name")
    local created_id=$(echo "$create_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$created_id" "Folder created for find test"; then
        TEST_FOLDERS+=("$created_id")

        # Find the folder
        local find_output=$(gdrive find-folder "$unique_name")

        assert_contains "$find_output" "$created_id" "Found folder by name"
        assert_contains "$find_output" "$unique_name" "Found output contains folder name"
    fi
}

test_find_nonexistent_folder() {
    # Test: Find folder that doesn't exist
    local nonexistent="nonexistent_folder_$(date +%s)_xyz"
    local find_output=$(gdrive find-folder "$nonexistent" 2>/dev/null || echo "")

    assert_equals "" "$find_output" "No results for nonexistent folder"
}

test_upload_file_to_folder() {
    # Test: Upload file to a specific folder
    local folder_name="upload_target_$(date +%s)"
    local create_output=$(gdrive create-folder "$folder_name")
    local folder_id=$(echo "$create_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$folder_id" "Target folder created"; then
        TEST_FOLDERS+=("$folder_id")

        # Upload a file to this folder
        local test_file=$(create_test_file "in_folder.txt" "I'm in a folder!")
        local upload_output=$(gdrive upload "$test_file" "in_folder.txt" "$folder_id")
        local file_id=$(echo "$upload_output" | jq -r '.id' 2>/dev/null || echo "")

        if assert_not_empty "$file_id" "File uploaded to folder"; then
            # Verify file is in folder
            local folder_contents=$(gdrive list "$folder_id" 2>/dev/null)
            assert_contains "$folder_contents" "in_folder.txt" "File is in correct folder"

            # Clean up file
            gdrive_silent delete "$file_id"
        fi
    fi
}

test_list_folder_contents() {
    # Test: List contents of a folder
    local folder_name="list_test_$(date +%s)"
    local create_output=$(gdrive create-folder "$folder_name")
    local folder_id=$(echo "$create_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$folder_id" "Folder created for listing test"; then
        TEST_FOLDERS+=("$folder_id")

        # Upload multiple files to folder
        local file_ids=()
        for i in {1..3}; do
            local file_id=$(upload_test_file "file_$i.txt" "Content $i" "$folder_id")
            file_ids+=("$file_id")
        done

        # List folder contents
        local list_output=$(gdrive list "$folder_id")

        for i in {1..3}; do
            assert_contains "$list_output" "file_$i.txt" "Folder contains file_$i.txt"
        done

        # Clean up files
        for file_id in "${file_ids[@]}"; do
            gdrive_silent delete "$file_id"
        done
    fi
}

test_rename_folder() {
    # Test: Rename a folder
    local old_name="old_folder_name_$(date +%s)"
    local new_name="new_folder_name_$(date +%s)"

    local create_output=$(gdrive create-folder "$old_name")
    local folder_id=$(echo "$create_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$folder_id" "Folder created for rename test"; then
        TEST_FOLDERS+=("$folder_id")

        # Rename the folder
        gdrive rename "$folder_id" "$new_name"

        # Verify rename
        local folder_info=$(gdrive info "$folder_id" 2>/dev/null)
        assert_contains "$folder_info" "$new_name" "Folder renamed successfully"
    fi
}

test_delete_empty_folder() {
    # Test: Delete an empty folder
    local folder_name="delete_me_$(date +%s)"
    local create_output=$(gdrive create-folder "$folder_name")
    local folder_id=$(echo "$create_output" | jq -r '.id' 2>/dev/null || echo "")

    if assert_not_empty "$folder_id" "Folder created for deletion test"; then
        # Delete the folder
        gdrive delete "$folder_id"

        # Try to get info - should fail
        if ! gdrive_silent info "$folder_id"; then
            pass "Folder deleted successfully"
        else
            fail "Folder still exists after deletion"
            TEST_FOLDERS+=("$folder_id")  # Add for cleanup if deletion failed
        fi
    fi
}

test_move_folder() {
    # Test: Move folder to another folder
    local parent_name="parent_$(date +%s)"
    local child_name="child_$(date +%s)"
    local new_parent_name="new_parent_$(date +%s)"

    # Create folders
    local parent_output=$(gdrive create-folder "$parent_name")
    local parent_id=$(echo "$parent_output" | jq -r '.id' 2>/dev/null || echo "")

    local child_output=$(gdrive create-folder "$child_name" "$parent_id")
    local child_id=$(echo "$child_output" | jq -r '.id' 2>/dev/null || echo "")

    local new_parent_output=$(gdrive create-folder "$new_parent_name")
    local new_parent_id=$(echo "$new_parent_output" | jq -r '.id' 2>/dev/null || echo "")

    TEST_FOLDERS+=("$parent_id" "$child_id" "$new_parent_id")

    if [[ -n "$child_id" ]] && [[ -n "$new_parent_id" ]]; then
        # Move child to new parent
        gdrive move "$child_id" "$new_parent_id"

        # Verify child is in new parent
        local new_parent_contents=$(gdrive list "$new_parent_id" 2>/dev/null)
        assert_contains "$new_parent_contents" "$child_name" "Folder moved to new parent"

        # Verify child is not in old parent
        local old_parent_contents=$(gdrive list "$parent_id" 2>/dev/null)
        if [[ "$old_parent_contents" == *"$child_name"* ]]; then
            fail "Folder still in old parent after move"
        else
            pass "Folder removed from old parent"
        fi
    else
        fail "Could not create folders for move test"
    fi
}

# Main test execution
main() {
    init_test_env

    # Check authentication first
    if ! gdrive_silent list; then
        echo -e "${YELLOW}Skipping folder operations tests - not authenticated${NC}"
        exit 0
    fi

    run_test_suite "Folder Operations Tests" \
        test_create_folder \
        test_create_nested_folder \
        test_find_folder_by_name \
        test_find_nonexistent_folder \
        test_upload_file_to_folder \
        test_list_folder_contents \
        test_rename_folder \
        test_delete_empty_folder \
        test_move_folder

    teardown

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi