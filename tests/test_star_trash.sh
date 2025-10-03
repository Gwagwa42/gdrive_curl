#!/usr/bin/env bash
set -euo pipefail

# Load test framework
source "$(dirname "$0")/test_helpers.sh"

# Star and Trash Management Tests

# Track test files
TEST_FILES=()

teardown() {
    # Clean up test files
    for file_id in "${TEST_FILES[@]}"; do
        if [[ -n "$file_id" ]]; then
            # Try to restore from trash first, then delete
            gdrive_silent restore "$file_id"
            gdrive_silent delete "$file_id"
        fi
    done
}

# === Star Management Tests ===

test_star_file() {
    # Test: Star a file
    local file_id=$(upload_test_file "star_me.txt" "Star this file")

    if assert_not_empty "$file_id" "File created for star test"; then
        TEST_FILES+=("$file_id")

        local star_output=$(gdrive star "$file_id" 2>&1)
        assert_contains "$star_output" "starred" "File starred successfully"

        # Verify file appears in starred list
        local starred_files=$(gdrive get-starred 2>/dev/null)
        assert_contains "$starred_files" "star_me.txt" "File appears in starred list"
    fi
}

test_unstar_file() {
    # Test: Unstar a file
    local file_id=$(upload_test_file "unstar_me.txt" "Unstar this file")

    if assert_not_empty "$file_id" "File created for unstar test"; then
        TEST_FILES+=("$file_id")

        # First star it
        gdrive star "$file_id" >/dev/null 2>&1

        # Then unstar it
        local unstar_output=$(gdrive unstar "$file_id" 2>&1)
        assert_contains "$unstar_output" "unstarred" "File unstarred successfully"

        # Verify file no longer in starred list
        local starred_files=$(gdrive get-starred 2>/dev/null)
        if echo "$starred_files" | grep -q "unstar_me.txt"; then
            fail "File still in starred list after unstar"
        else
            pass "File removed from starred list"
        fi
    fi
}

test_get_starred_files() {
    # Test: List starred files
    # Star multiple files
    local file1=$(upload_test_file "starred1.txt" "First starred")
    local file2=$(upload_test_file "starred2.txt" "Second starred")
    local file3=$(upload_test_file "not_starred.txt" "Not starred")

    TEST_FILES+=("$file1" "$file2" "$file3")

    if [[ -n "$file1" ]] && [[ -n "$file2" ]]; then
        # Star only file1 and file2
        gdrive star "$file1" >/dev/null 2>&1
        gdrive star "$file2" >/dev/null 2>&1

        # Get starred files
        local starred_list=$(gdrive get-starred 2>/dev/null)

        assert_contains "$starred_list" "starred1.txt" "First starred file in list"
        assert_contains "$starred_list" "starred2.txt" "Second starred file in list"

        if echo "$starred_list" | grep -q "not_starred.txt"; then
            fail "Unstarred file appears in starred list"
        else
            pass "Unstarred file not in starred list"
        fi
    else
        fail "Could not create files for starred list test"
    fi
}

test_star_unstar_workflow() {
    # Test: Complete star/unstar workflow
    local file_id=$(upload_test_file "workflow_star.txt" "Star workflow")

    if assert_not_empty "$file_id" "File created for workflow"; then
        TEST_FILES+=("$file_id")

        # 1. Star the file
        gdrive star "$file_id" >/dev/null 2>&1

        # 2. Verify it's starred
        local starred=$(gdrive get-starred 2>/dev/null)
        assert_contains "$starred" "workflow_star.txt" "File is starred"

        # 3. Unstar the file
        gdrive unstar "$file_id" >/dev/null 2>&1

        # 4. Verify it's not starred
        local unstarred=$(gdrive get-starred 2>/dev/null)
        if echo "$unstarred" | grep -q "workflow_star.txt"; then
            fail "File still starred after unstar"
        else
            pass "File successfully unstarred"
        fi
    fi
}

# === Trash Management Tests ===

test_trash_file() {
    # Test: Move file to trash
    local file_id=$(upload_test_file "trash_me.txt" "Send to trash")

    if assert_not_empty "$file_id" "File created for trash test"; then
        TEST_FILES+=("$file_id")

        local trash_output=$(gdrive trash "$file_id" 2>&1)
        assert_contains "$trash_output" "moved to trash" "File moved to trash"

        # Verify file is in trash
        local trash_list=$(gdrive list-trash 2>/dev/null)
        assert_contains "$trash_list" "trash_me.txt" "File appears in trash"
    fi
}

test_list_trash() {
    # Test: List files in trash
    # Create and trash multiple files
    local file1=$(upload_test_file "trash1.txt" "First trash")
    local file2=$(upload_test_file "trash2.txt" "Second trash")
    local file3=$(upload_test_file "keep.txt" "Keep this")

    TEST_FILES+=("$file1" "$file2" "$file3")

    if [[ -n "$file1" ]] && [[ -n "$file2" ]]; then
        # Trash only file1 and file2
        gdrive trash "$file1" >/dev/null 2>&1
        gdrive trash "$file2" >/dev/null 2>&1

        # List trash
        local trash_list=$(gdrive list-trash 2>/dev/null)

        assert_contains "$trash_list" "trash1.txt" "First file in trash"
        assert_contains "$trash_list" "trash2.txt" "Second file in trash"

        if echo "$trash_list" | grep -q "keep.txt"; then
            fail "Non-trashed file appears in trash"
        else
            pass "Non-trashed file not in trash list"
        fi
    else
        fail "Could not create files for trash list test"
    fi
}

test_restore_from_trash() {
    # Test: Restore file from trash
    local file_id=$(upload_test_file "restore_me.txt" "Restore this")

    if assert_not_empty "$file_id" "File created for restore test"; then
        TEST_FILES+=("$file_id")

        # Trash the file
        gdrive trash "$file_id" >/dev/null 2>&1

        # Restore it
        local restore_output=$(gdrive restore "$file_id" 2>&1)
        assert_contains "$restore_output" "restored from trash" "File restored"

        # Verify file is not in trash anymore
        local trash_list=$(gdrive list-trash 2>/dev/null)
        if echo "$trash_list" | grep -q "restore_me.txt"; then
            fail "File still in trash after restore"
        else
            pass "File removed from trash"
        fi

        # Verify file is in regular list
        local file_info=$(gdrive info "$file_id" 2>/dev/null)
        assert_contains "$file_info" '"trashed": false' "File is not trashed"
    fi
}

test_delete_permanently() {
    # Test: Permanently delete a file
    local file_id=$(upload_test_file "delete_forever.txt" "Delete permanently")

    if assert_not_empty "$file_id" "File created for permanent delete test"; then
        # Delete permanently
        local delete_output=$(gdrive delete "$file_id" 2>&1)
        assert_contains "$delete_output" "permanently deleted" "File permanently deleted"

        # Verify file doesn't exist
        if ! gdrive_silent info "$file_id"; then
            pass "File no longer exists"
        else
            fail "File still exists after permanent deletion"
            TEST_FILES+=("$file_id")  # Add for cleanup if still exists
        fi
    fi
}

test_trash_restore_workflow() {
    # Test: Complete trash/restore workflow
    local file_id=$(upload_test_file "trash_workflow.txt" "Trash workflow test")

    if assert_not_empty "$file_id" "File created for workflow"; then
        TEST_FILES+=("$file_id")

        # 1. File should not be in trash initially
        local initial_trash=$(gdrive list-trash 2>/dev/null)
        if echo "$initial_trash" | grep -q "trash_workflow.txt"; then
            fail "File in trash before trashing"
        else
            pass "File not in trash initially"
        fi

        # 2. Trash the file
        gdrive trash "$file_id" >/dev/null 2>&1

        # 3. Verify it's in trash
        local after_trash=$(gdrive list-trash 2>/dev/null)
        assert_contains "$after_trash" "trash_workflow.txt" "File in trash after trashing"

        # 4. Restore the file
        gdrive restore "$file_id" >/dev/null 2>&1

        # 5. Verify it's not in trash
        local after_restore=$(gdrive list-trash 2>/dev/null)
        if echo "$after_restore" | grep -q "trash_workflow.txt"; then
            fail "File still in trash after restore"
        else
            pass "File restored from trash"
        fi
    fi
}

test_list_trash_pagination() {
    # Test: List trash with pagination
    # This tests that pagination parameter works
    local trash_output=$(gdrive list-trash 5 2>/dev/null || echo "")

    # Should not fail even with pagination
    if [[ -n "$trash_output" ]] || [[ $? -eq 0 ]]; then
        pass "List trash with pagination works"
    else
        fail "List trash with pagination failed"
    fi
}

# Main test execution
main() {
    init_test_env

    # Check authentication first
    if ! gdrive_silent list; then
        echo -e "${YELLOW}Skipping star/trash tests - not authenticated${NC}"
        exit 0
    fi

    run_test_suite "Star and Trash Management Tests" \
        test_star_file \
        test_unstar_file \
        test_get_starred_files \
        test_star_unstar_workflow \
        test_trash_file \
        test_list_trash \
        test_restore_from_trash \
        test_delete_permanently \
        test_trash_restore_workflow \
        test_list_trash_pagination

    teardown

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi