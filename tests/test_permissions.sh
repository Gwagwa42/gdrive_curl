#!/usr/bin/env bash
set -euo pipefail

# Load test framework
source "$(dirname "$0")/test_helpers.sh"

# Permission Management Tests

# Track test files
TEST_FILE_ID=""
SHARE_PERMISSION_ID=""

setup() {
    # Create a test file for permission tests
    TEST_FILE_ID=$(upload_test_file "permission_test.txt" "Testing permissions")
    assert_not_empty "$TEST_FILE_ID" "Test file created for permission tests"
}

teardown() {
    # Clean up test file
    if [[ -n "$TEST_FILE_ID" ]]; then
        cleanup_test_file "$TEST_FILE_ID"
    fi
}

test_share_file_reader() {
    # Test: Share file with reader permission
    local share_output=$(gdrive share "$TEST_FILE_ID" reader 2>&1)

    assert_contains "$share_output" "Share link created" "Share link created successfully"
    assert_contains "$share_output" "reader permission" "Has reader permission"
    assert_contains "$share_output" "drive.google.com" "Contains Google Drive URL"
}

test_share_file_writer() {
    # Test: Share file with writer permission
    local file_id=$(upload_test_file "share_writer.txt" "Writer test")

    if [[ -n "$file_id" ]]; then
        local share_output=$(gdrive share "$file_id" writer 2>&1)

        assert_contains "$share_output" "Share link created" "Share link created for writer"
        assert_contains "$share_output" "writer permission" "Has writer permission"

        cleanup_test_file "$file_id"
    else
        fail "Could not create file for writer share test"
    fi
}

test_share_file_commenter() {
    # Test: Share file with commenter permission
    local file_id=$(upload_test_file "share_commenter.txt" "Commenter test")

    if [[ -n "$file_id" ]]; then
        local share_output=$(gdrive share "$file_id" commenter 2>&1)

        assert_contains "$share_output" "Share link created" "Share link created for commenter"
        assert_contains "$share_output" "commenter permission" "Has commenter permission"

        cleanup_test_file "$file_id"
    else
        fail "Could not create file for commenter share test"
    fi
}

test_share_invalid_role() {
    # Test: Share with invalid role should fail
    # Note: gdrive wrapper redirects stderr to log, so we need to check exit code only
    if gdrive share "$TEST_FILE_ID" "invalid_role" >/dev/null 2>&1; then
        fail "Should reject invalid role with non-zero exit code"
    else
        pass "Correctly rejects invalid role"
    fi
}

test_list_permissions() {
    # Test: List permissions on a file
    # First share the file to create a permission
    gdrive share "$TEST_FILE_ID" reader >/dev/null 2>&1

    local permissions=$(gdrive list-permissions "$TEST_FILE_ID" 2>/dev/null)

    # Should have at least owner permission
    assert_not_empty "$permissions" "Permissions list is not empty"

    # Check for expected columns (permission ID, type, role)
    if echo "$permissions" | grep -qE "owner|reader|writer"; then
        pass "Permissions list contains roles"
    else
        fail "Permissions list missing role information"
    fi
}

test_list_permissions_after_share() {
    # Test: List permissions shows new permission after sharing
    local file_id=$(upload_test_file "list_perms.txt" "Permission listing test")

    if [[ -n "$file_id" ]]; then
        # Share the file
        gdrive share "$file_id" writer >/dev/null 2>&1

        # List permissions
        local permissions=$(gdrive list-permissions "$file_id" 2>/dev/null)

        # Should show 'anyone' permission with writer role
        assert_contains "$permissions" "anyone" "Shows anyone permission"
        assert_contains "$permissions" "writer" "Shows writer role"

        cleanup_test_file "$file_id"
    else
        fail "Could not create file for permission list test"
    fi
}

test_delete_permission() {
    # Test: Delete a permission
    local file_id=$(upload_test_file "delete_perm.txt" "Delete permission test")

    if [[ -n "$file_id" ]]; then
        # Share the file to create a permission
        gdrive share "$file_id" reader >/dev/null 2>&1

        # Get the permission ID
        local perm_line=$(gdrive list-permissions "$file_id" 2>/dev/null | grep "anyone" | head -n 1)
        local perm_id=$(echo "$perm_line" | awk '{print $1}')

        if assert_not_empty "$perm_id" "Found permission ID to delete"; then
            # Delete the permission
            local delete_output=$(gdrive delete-permission "$file_id" "$perm_id" 2>&1)
            assert_contains "$delete_output" "deleted" "Permission deleted message"

            # Verify permission is gone
            local remaining_perms=$(gdrive list-permissions "$file_id" 2>/dev/null)
            if echo "$remaining_perms" | grep -q "$perm_id"; then
                fail "Permission still exists after deletion"
            else
                pass "Permission successfully removed"
            fi
        fi

        cleanup_test_file "$file_id"
    else
        fail "Could not create file for delete permission test"
    fi
}

test_update_permission() {
    # Test: Update permission role
    local file_id=$(upload_test_file "update_perm.txt" "Update permission test")

    if [[ -n "$file_id" ]]; then
        # Share with reader permission
        gdrive share "$file_id" reader >/dev/null 2>&1

        # Get the permission ID
        local perm_line=$(gdrive list-permissions "$file_id" 2>/dev/null | grep "anyone" | head -n 1)
        local perm_id=$(echo "$perm_line" | awk '{print $1}')

        if assert_not_empty "$perm_id" "Found permission ID to update"; then
            # Update to writer
            local update_output=$(gdrive update-permission "$file_id" "$perm_id" writer 2>&1)
            assert_contains "$update_output" "updated to writer" "Permission updated message"

            # Verify role changed
            local updated_perms=$(gdrive list-permissions "$file_id" 2>/dev/null)
            assert_contains "$updated_perms" "writer" "Permission role changed to writer"
        fi

        cleanup_test_file "$file_id"
    else
        fail "Could not create file for update permission test"
    fi
}

test_update_permission_invalid_role() {
    # Test: Update with invalid role should fail
    # First create a permission
    gdrive share "$TEST_FILE_ID" reader >/dev/null 2>&1

    # Get the permission ID
    local perm_line=$(gdrive list-permissions "$TEST_FILE_ID" 2>/dev/null | grep "anyone" | head -n 1)
    local perm_id=$(echo "$perm_line" | awk '{print $1}')

    if [[ -n "$perm_id" ]]; then
        # Note: gdrive wrapper redirects stderr to log, so we need to check exit code only
        if gdrive update-permission "$TEST_FILE_ID" "$perm_id" "invalid_role" >/dev/null 2>&1; then
            fail "Should reject invalid role in update with non-zero exit code"
        else
            pass "Correctly rejects invalid role in update"
        fi
    else
        skip_test "Update invalid role test" "Could not get permission ID"
    fi
}

test_permissions_workflow() {
    # Test: Complete permissions workflow
    local file_id=$(upload_test_file "workflow.txt" "Complete workflow test")

    if [[ -n "$file_id" ]]; then
        # 1. Share file
        local share_output=$(gdrive share "$file_id" reader 2>&1)
        assert_contains "$share_output" "Share link created" "Step 1: File shared"

        # 2. List permissions
        local perms=$(gdrive list-permissions "$file_id" 2>/dev/null)
        assert_contains "$perms" "reader" "Step 2: Permission listed"

        # 3. Get permission ID
        local perm_id=$(echo "$perms" | grep "anyone" | awk '{print $1}')
        assert_not_empty "$perm_id" "Step 3: Got permission ID"

        # 4. Update permission
        gdrive update-permission "$file_id" "$perm_id" writer 2>&1
        local updated_perms=$(gdrive list-permissions "$file_id" 2>/dev/null)
        assert_contains "$updated_perms" "writer" "Step 4: Permission updated"

        # 5. Delete permission
        gdrive delete-permission "$file_id" "$perm_id" 2>&1
        local final_perms=$(gdrive list-permissions "$file_id" 2>/dev/null | grep "anyone" || true)
        assert_equals "" "$final_perms" "Step 5: Permission deleted"

        cleanup_test_file "$file_id"
    else
        fail "Could not create file for workflow test"
    fi
}

# Main test execution
main() {
    init_test_env

    # Check authentication first
    if ! gdrive_silent list; then
        echo -e "${YELLOW}Skipping permission tests - not authenticated${NC}"
        exit 0
    fi

    setup

    run_test_suite "Permission Management Tests" \
        test_share_file_reader \
        test_share_file_writer \
        test_share_file_commenter \
        test_share_invalid_role \
        test_list_permissions \
        test_list_permissions_after_share \
        test_delete_permission \
        test_update_permission \
        test_update_permission_invalid_role \
        test_permissions_workflow

    teardown

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi