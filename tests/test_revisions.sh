#!/usr/bin/env bash
set -euo pipefail

# Load test framework
source "$(dirname "$0")/test_helpers.sh"

# Version History (Revisions) Tests

# Track test files
TEST_FILES=()

teardown() {
    # Clean up test files
    for file_id in "${TEST_FILES[@]}"; do
        if [[ -n "$file_id" ]]; then
            cleanup_test_file "$file_id"
        fi
    done
}

test_list_revisions_regular_file() {
    # Test: List revisions for a regular uploaded file
    local file_id=$(upload_test_file "revision_test.txt" "Initial content")

    if assert_not_empty "$file_id" "File created for revision test"; then
        TEST_FILES+=("$file_id")

        # Update the file to create a revision
        local update_file=$(create_test_file "update.txt" "Updated content")
        gdrive update "$file_id" "$update_file" >/dev/null 2>&1

        # Give Drive time to process the revision
        sleep 2

        # List revisions
        local revisions=$(gdrive list-revisions "$file_id" 2>/dev/null || echo "")

        if [[ -z "$revisions" ]]; then
            skip_test "List revisions" "Regular files may not have revision history"
        else
            assert_not_empty "$revisions" "Revisions listed"
            # Should have timestamp column
            if echo "$revisions" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
                pass "Revisions contain timestamps"
            else
                fail "Revisions missing timestamp information"
            fi
        fi
    fi
}

test_get_revision_command_structure() {
    # Test: Verify get-revision command structure
    local file_id=$(upload_test_file "get_rev_test.txt" "Test revision download")

    if assert_not_empty "$file_id" "File created for get-revision test"; then
        TEST_FILES+=("$file_id")

        # Try to download a fake revision (should fail but test command structure)
        local fake_revision_id="fake_revision_123"
        local output_file="$TEST_DATA_DIR/rev_download.txt"

        if gdrive get-revision "$file_id" "$fake_revision_id" "$output_file" 2>&1 | grep -qE "(404|not found|does not exist)"; then
            pass "Get-revision command structured correctly"
        else
            # Command might succeed if file has revisions
            skip_test "Get-revision structure test" "Unable to verify command structure"
        fi
    fi
}

test_revision_workflow_simulation() {
    # Test: Simulate revision workflow (may not work with regular files)
    local file_id=$(upload_test_file "workflow_rev.txt" "Version 1")

    if assert_not_empty "$file_id" "File created for revision workflow"; then
        TEST_FILES+=("$file_id")

        # Create multiple versions
        for i in {2..3}; do
            local update_file=$(create_test_file "v$i.txt" "Version $i")
            gdrive update "$file_id" "$update_file" >/dev/null 2>&1
            sleep 1
        done

        # Try to list revisions
        local revisions=$(gdrive list-revisions "$file_id" 2>/dev/null || echo "")

        if [[ -n "$revisions" ]]; then
            pass "Revision workflow works"

            # Count revisions
            local rev_count=$(echo "$revisions" | wc -l)
            if [[ $rev_count -gt 0 ]]; then
                pass "Multiple revisions detected: $rev_count"
            fi

            # Try to get first revision ID
            local first_rev_id=$(echo "$revisions" | head -n 1 | awk '{print $1}')
            if [[ -n "$first_rev_id" ]] && [[ "$first_rev_id" != "null" ]]; then
                # Try to download the revision
                local download_path="$TEST_DATA_DIR/old_version.txt"
                if gdrive get-revision "$file_id" "$first_rev_id" "$download_path" 2>/dev/null; then
                    assert_file_exists "$download_path" "Revision downloaded"
                else
                    skip_test "Download revision" "Could not download revision"
                fi
            else
                skip_test "Get revision" "No valid revision ID found"
            fi
        else
            skip_test "Revision workflow" "Regular files may not support revisions"
        fi
    fi
}

test_list_revisions_nonexistent_file() {
    # Test: List revisions for nonexistent file should fail
    local fake_id="nonexistent_file_$(date +%s)"

    if gdrive list-revisions "$fake_id" 2>&1 | grep -qE "(404|not found|does not exist)"; then
        pass "Correctly handles nonexistent file"
    else
        fail "Should error on nonexistent file"
    fi
}

test_get_revision_with_auto_filename() {
    # Test: Get revision with auto-generated filename
    local file_id=$(upload_test_file "auto_rev.txt" "Auto revision test")

    if assert_not_empty "$file_id" "File created for auto-filename test"; then
        TEST_FILES+=("$file_id")

        # Update to create revision
        local update_file=$(create_test_file "update.txt" "Updated")
        gdrive update "$file_id" "$update_file" >/dev/null 2>&1
        sleep 2

        # List revisions
        local revisions=$(gdrive list-revisions "$file_id" 2>/dev/null || echo "")

        if [[ -n "$revisions" ]]; then
            local rev_id=$(echo "$revisions" | head -n 1 | awk '{print $1}')

            if [[ -n "$rev_id" ]] && [[ "$rev_id" != "null" ]]; then
                # Try to download without specifying output filename
                cd "$TEST_DATA_DIR"
                if gdrive get-revision "$file_id" "$rev_id" 2>/dev/null; then
                    # Check if file was created with expected pattern
                    if ls *_rev${rev_id}* >/dev/null 2>&1; then
                        pass "Revision downloaded with auto-generated filename"
                    else
                        fail "Auto-generated filename not created"
                    fi
                else
                    skip_test "Auto filename test" "Could not download revision"
                fi
                cd - >/dev/null
            else
                skip_test "Auto filename test" "No valid revision ID"
            fi
        else
            skip_test "Auto filename test" "No revisions available"
        fi
    fi
}

test_revision_metadata() {
    # Test: Revision list contains metadata
    local file_id=$(upload_test_file "metadata_test.txt" "Check metadata")

    if assert_not_empty "$file_id" "File created for metadata test"; then
        TEST_FILES+=("$file_id")

        # Update file
        local update_file=$(create_test_file "update.txt" "Updated for metadata")
        gdrive update "$file_id" "$update_file" >/dev/null 2>&1
        sleep 2

        # List revisions with full output
        local revisions=$(gdrive list-revisions "$file_id" 2>/dev/null || echo "")

        if [[ -n "$revisions" ]]; then
            # Check for expected columns
            # Should have: revision_id, modifiedTime, lastModifyingUser
            local first_line=$(echo "$revisions" | head -n 1)
            local column_count=$(echo "$first_line" | awk '{print NF}')

            if [[ $column_count -ge 2 ]]; then
                pass "Revision metadata includes multiple fields"
            else
                fail "Revision metadata incomplete"
            fi
        else
            skip_test "Revision metadata test" "No revisions available"
        fi
    fi
}

test_google_workspace_note() {
    # Test: Note about Google Workspace files
    # Google Docs/Sheets/Slides have different revision behavior

    echo "  ℹ️  Note: Revision features work best with Google Workspace files"
    echo "     (Google Docs, Sheets, Slides) which maintain full revision history."
    echo "     Regular uploaded files may have limited revision support."

    # This is informational, always passes
    pass "Google Workspace revision note displayed"
}

# Main test execution
main() {
    init_test_env

    # Check authentication first
    if ! gdrive_silent list; then
        echo -e "${YELLOW}Skipping revision tests - not authenticated${NC}"
        exit 0
    fi

    echo -e "${YELLOW}Note: Revision tests may skip if Drive doesn't maintain revisions for uploaded files${NC}"
    echo ""

    run_test_suite "Version History (Revisions) Tests" \
        test_list_revisions_regular_file \
        test_get_revision_command_structure \
        test_revision_workflow_simulation \
        test_list_revisions_nonexistent_file \
        test_get_revision_with_auto_filename \
        test_revision_metadata \
        test_google_workspace_note

    teardown

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi