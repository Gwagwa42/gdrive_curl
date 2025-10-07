# gdrive_curl 🚀

A lightweight, standalone bash script for Google Drive file management using OAuth 2.0 device flow authentication. No heavy dependencies - just `curl`, `jq`, and `file`.

## Features

### Core Functionality
- ✅ **File Upload/Download** - Multipart & resumable uploads, smart downloads with filename detection
- ✅ **File Management** - List, rename, move, copy, update, delete, trash, and restore files
- ✅ **Folder Operations** - Create folders, find by name, navigate hierarchy
- ✅ **Sharing & Permissions** - Create shareable links, manage access permissions
- ✅ **Advanced Search** - Full Google Drive API query syntax support
- ✅ **Google Workspace Export** - Export Docs/Sheets/Slides to standard formats
- ✅ **Storage Management** - Check quota, manage starred files, browse trash
- ✅ **Version Control** - Access and download file revision history
- ✅ **Cross-platform** - Works on macOS and Linux

### Key Advantages
- **Minimal Dependencies** - Only requires `curl`, `jq`, and `file` commands
- **Single File** - ~900 lines of pure bash, no installation required
- **OAuth 2.0 Device Flow** - Secure authentication without storing passwords
- **Automatic Token Management** - Handles refresh tokens automatically
- **Shell Composable** - Unix philosophy design for scripting and automation

## Table of Contents

- [Installation](#installation)
- [Authentication Setup](#authentication-setup)
- [Quick Start](#quick-start)
- [Commands Reference](#commands-reference)
- [Usage Examples](#usage-examples)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Installation

### Prerequisites

```bash
# macOS
brew install curl jq

# Ubuntu/Debian
sudo apt-get install curl jq file

# Fedora/RHEL
sudo dnf install curl jq file
```

### Download

```bash
# Clone the repository
git clone https://github.com/yourusername/gdrive_curl.git
cd gdrive_curl

# Or download directly
curl -O https://raw.githubusercontent.com/yourusername/gdrive_curl/main/gdrive_curl.sh
chmod +x gdrive_curl.sh
```

## Authentication Setup

### ⚠️ Important: OAuth Client Required

You **MUST** create your own OAuth credentials. The script no longer includes default credentials for security reasons.

### Understanding OAuth Scopes

The script supports two authorization modes:

#### **App-Only Mode** (`drive.file` scope) - DEFAULT
- ✅ **More secure** - Only accesses files created by this app
- ✅ **Easier approval** - No Google verification needed
- ✅ **Privacy-focused** - Can't see your existing files
- ❌ **Limited functionality** - Can't list/download existing Drive files
- 📁 **Use when**: Creating backup tools, log uploaders, app-specific storage

#### **Full Access Mode** (`drive` scope)
- ✅ **Complete functionality** - Access all Drive files
- ✅ **Full search** - Find any file in your Drive
- ✅ **Existing files** - Download, modify, organize all files
- ⚠️ **Requires trust** - App can see/modify everything
- 📁 **Use when**: File managers, backup tools for existing files, Drive organizers

### Selecting Scope Mode

```bash
# Method 1: Command-line flags (per-command)
./gdrive_curl.sh --full-access list           # List all files
./gdrive_curl.sh --app-only upload file.txt   # Upload with restricted access

# Method 2: Environment variable (session-wide)
export SCOPE_MODE=full
./gdrive_curl.sh list                         # Uses full access

# Method 3: Per-command override
SCOPE_MODE=full ./gdrive_curl.sh init         # One-time full access

# Check current scope configuration
./gdrive_curl.sh scope
```

**Important**: Different scopes use different token files:
- App-only: `~/.config/gdrive-curl/tokens-app.json`
- Full access: `~/.config/gdrive-curl/tokens-full.json`

This means you can have both authorizations active and switch between them.

### Creating OAuth Credentials

1. **Go to [Google Cloud Console](https://console.cloud.google.com/)**

2. **Create or select a project**

3. **Enable Google Drive API**:
   ```
   APIs & Services → Library → Search "Google Drive API" → Enable
   ```

4. **Create OAuth 2.0 Credentials**:
   ```
   APIs & Services → Credentials → Create Credentials → OAuth client ID
   ```
   - Application type: **TV and Limited Input devices**
   - Name: Your app name

5. **Configure OAuth Consent Screen**:
   ```
   APIs & Services → OAuth consent screen
   ```
   - Add scopes: `https://www.googleapis.com/auth/drive`
   - Add test users if in testing mode

6. **Use your credentials**:
   ```bash
   export CLIENT_ID="your-client-id.apps.googleusercontent.com"
   export CLIENT_SECRET="your-client-secret"
   ./gdrive_curl.sh init
   ```

   **Note for Testing**: These environment variables must be exported for the test suite to work:
   ```bash
   # Export credentials before running tests
   export CLIENT_ID="your-client-id.apps.googleusercontent.com"
   export CLIENT_SECRET="your-client-secret"
   make test
   ```

### First Time Authentication

```bash
# Initialize authentication
./gdrive_curl.sh init

# You'll see:
# 1) Visit: https://www.google.com/device
# 2) Enter code: XXXX-XXXX
# Waiting for approval...

# After authorization:
# ✅ Auth complete. Tokens saved to ~/.config/gdrive-curl/tokens.json
```

## Quick Start

```bash
# Upload a file
./gdrive_curl.sh upload document.pdf

# Download a file
./gdrive_curl.sh download <file_id>

# List your files
./gdrive_curl.sh list

# Create a folder
./gdrive_curl.sh create-folder "My Project"

# Search for files
./gdrive_curl.sh search "name contains 'report'"

# Share a file
./gdrive_curl.sh share <file_id> reader
```

## Commands Reference

### Authentication & Configuration
| Command | Description |
|---------|------------|
| `init` | Start OAuth device flow and save tokens |
| `scope` | Show current scope mode and authentication status |

### File Operations
| Command | Description |
|---------|------------|
| `upload <file> [name] [parent_id]` | Upload file (multipart, ≤5MB) |
| `upload-big <file> [name] [parent_id]` | Upload large file (resumable) |
| `download <file_id> [output_path]` | Download file (auto-detects name) |
| `update <file_id> <local_file>` | Update existing file content |
| `copy <file_id> [name] [parent_id]` | Copy file |
| `rename <file_id> <new_name>` | Rename file or folder |
| `move <file_id> <new_parent_id>` | Move file to different folder |
| `trash <file_id>` | Move to trash |
| `restore <file_id>` | Restore from trash |
| `delete <file_id>` | Permanently delete |

### Folder Operations
| Command | Description |
|---------|------------|
| `create-folder <name> [parent_id]` | Create new folder |
| `find-folder <name>` | Find folder by name |
| `list [parent_id] [page_size]` | List files in folder |

### Sharing & Permissions
| Command | Description |
|---------|------------|
| `share <file_id> [role]` | Create shareable link (reader/writer/commenter) |
| `list-permissions <file_id>` | List all permissions |
| `update-permission <file_id> <perm_id> <role>` | Update permission role |
| `delete-permission <file_id> <perm_id>` | Revoke permission |

### Search & Discovery
| Command | Description |
|---------|------------|
| `search <query> [page_size]` | Search with Drive API query syntax |
| `info <file_id>` | Get detailed file metadata |
| `get-starred` | List starred files |
| `list-trash [page_size]` | List files in trash |

### Export & Conversion
| Command | Description |
|---------|------------|
| `export <file_id> <format> [output]` | Export Google Workspace files |

### File Management
| Command | Description |
|---------|------------|
| `star <file_id>` | Star a file |
| `unstar <file_id>` | Remove star |
| `quota` | Show storage usage |
| `list-revisions <file_id>` | Show file versions |
| `get-revision <file_id> <rev_id> [output]` | Download specific version |

## Usage Examples

### Basic File Operations

```bash
# Upload multiple files
for file in *.pdf; do
    ./gdrive_curl.sh upload "$file"
done

# Download with original filename
./gdrive_curl.sh download abc123def

# Upload to specific folder
folder_id=$(./gdrive_curl.sh find-folder "Reports" | cut -f1)
./gdrive_curl.sh upload report.pdf "Q3 Report" "$folder_id"
```

### Advanced Search

```bash
# Find PDFs modified this year
./gdrive_curl.sh search "mimeType='application/pdf' and modifiedTime > '2024-01-01'"

# Find files shared with you
./gdrive_curl.sh search "sharedWithMe = true"

# Complex query
./gdrive_curl.sh search "name contains 'invoice' and modifiedTime > '2024-01-01' and starred = true"
```

### Batch Operations

```bash
# Upload directory recursively
find ./documents -type f -exec ./gdrive_curl.sh upload {} \;

# Parallel uploads (4 at a time)
ls *.jpg | xargs -P 4 -I {} ./gdrive_curl.sh upload {}

# Download search results
./gdrive_curl.sh search "name contains 'backup'" | \
    awk '{print $1}' | \
    xargs -I {} ./gdrive_curl.sh download {}

# Clean up old files
./gdrive_curl.sh search "modifiedTime < '2020-01-01'" | \
    awk '{print $1}' | \
    xargs -I {} ./gdrive_curl.sh trash {}
```

### Google Workspace Export

```bash
# Export Google Doc to PDF
./gdrive_curl.sh export doc123 pdf report.pdf

# Export Sheet to Excel
./gdrive_curl.sh export sheet456 xlsx data.xlsx

# Export Slides to PowerPoint
./gdrive_curl.sh export slides789 pptx presentation.pptx

# Batch export all Docs to PDF
./gdrive_curl.sh search "mimeType='application/vnd.google-apps.document'" | \
    awk '{print $1}' | \
    while read id; do
        ./gdrive_curl.sh export "$id" pdf "${id}.pdf"
    done
```

### Permission Management

```bash
# Share with view-only access
./gdrive_curl.sh share file123 reader

# Share with edit access
./gdrive_curl.sh share file123 writer

# Revoke specific user's access
./gdrive_curl.sh list-permissions file123
# Find the permission ID for the user
./gdrive_curl.sh delete-permission file123 permissionId456
```

### Folder Organization

```bash
# Create project structure
project_id=$(./gdrive_curl.sh create-folder "My Project" | jq -r '.id')
./gdrive_curl.sh create-folder "Documents" "$project_id"
./gdrive_curl.sh create-folder "Images" "$project_id"
./gdrive_curl.sh create-folder "Archive" "$project_id"

# Move files to folders
./gdrive_curl.sh move file123 "$project_id"
```

## Advanced Usage

### Environment Variables

```bash
# OAuth credentials (REQUIRED)
export CLIENT_ID="your-client-id.apps.googleusercontent.com"
export CLIENT_SECRET="your-client-secret"

# Scope mode selection (default: app)
export SCOPE_MODE="full"  # or "app" for restricted access

# Custom scope URL (overrides SCOPE_MODE)
export SCOPE="https://www.googleapis.com/auth/drive"

# Custom token storage location
export TOKENS_FILE="$HOME/.gdrive/tokens.json"

# Enable debug output for troubleshooting
export DEBUG=1
```

**Token File Locations by Mode**:
- App-only mode: `~/.config/gdrive-curl/tokens-app.json`
- Full access mode: `~/.config/gdrive-curl/tokens-full.json`
- Custom: Set via `TOKENS_FILE` environment variable

### Shell Integration

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Alias for convenience
alias gdrive="~/path/to/gdrive_curl.sh"

# Function to upload with progress
gdrive_upload() {
    local file="$1"
    echo "Uploading: $file"
    ~/path/to/gdrive_curl.sh upload "$file"
    echo "✓ Done"
}

# Function to backup directory
gdrive_backup() {
    local dir="$1"
    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    tar czf "/tmp/${backup_name}.tar.gz" "$dir"
    ~/path/to/gdrive_curl.sh upload-big "/tmp/${backup_name}.tar.gz"
    rm "/tmp/${backup_name}.tar.gz"
}
```

### Automation Examples

**Daily Backup Script**:
```bash
#!/bin/bash
# backup_to_drive.sh

BACKUP_DIR="/path/to/important/files"
GDRIVE="./gdrive_curl.sh"

# Create daily backup
tar czf backup_$(date +%Y%m%d).tar.gz "$BACKUP_DIR"

# Upload to Drive
$GDRIVE upload-big backup_*.tar.gz

# Clean up old backups (older than 30 days)
$GDRIVE search "name contains 'backup_' and modifiedTime < '$(date -d '30 days ago' +%Y-%m-%d)'" | \
    awk '{print $1}' | \
    xargs -I {} $GDRIVE trash {}
```

**Photo Sync Script**:
```bash
#!/bin/bash
# sync_photos.sh

PHOTO_DIR="$HOME/Pictures"
GDRIVE="./gdrive_curl.sh"

# Find Google Drive photos folder
DRIVE_FOLDER=$($GDRIVE find-folder "Photos" | cut -f1)

# Upload new photos only
find "$PHOTO_DIR" -name "*.jpg" -mtime -7 | while read photo; do
    filename=$(basename "$photo")
    # Check if already uploaded
    if ! $GDRIVE search "name = '$filename'" | grep -q "$filename"; then
        $GDRIVE upload "$photo" "$filename" "$DRIVE_FOLDER"
    fi
done
```

## Troubleshooting

### Common Issues

#### "invalid_scope" Error
**Problem**: OAuth client doesn't support Drive scope
```
Error: invalid_scope
Description: Invalid device flow scope
```
**Solution**: Create your own OAuth credentials (see [Authentication Setup](#authentication-setup))

#### "invalid_request" Error
**Problem**: Missing device_code parameter
**Solution**: The script now handles this automatically with proper error checking

#### Token Expired
**Problem**: Refresh token is invalid or expired
```
Failed to refresh token:
{
  "error": "invalid_grant",
  "error_description": "Token has been expired or revoked."
}
```
**Solution**:
1. Revoke access at https://myaccount.google.com/permissions
2. Delete tokens: `rm ~/.config/gdrive-curl/tokens.json`
3. Re-authenticate: `./gdrive_curl.sh init`

#### Rate Limiting
**Problem**: Too many requests
```
{
  "error": {
    "code": 429,
    "message": "Rate Limit Exceeded"
  }
}
```
**Solution**: Add delays between requests:
```bash
for file in *.pdf; do
    ./gdrive_curl.sh upload "$file"
    sleep 1  # Add 1 second delay
done
```

### Debug Mode

Enable debug output to see detailed API interactions:

```bash
# Enable debug mode
export DEBUG=1
./gdrive_curl.sh init

# Or for a single command
DEBUG=1 ./gdrive_curl.sh list
```

### File Size Limits

- **Multipart upload** (`upload`): Best for files ≤ 5MB
- **Resumable upload** (`upload-big`): Required for files > 5MB
- **Maximum file size**: 5TB (Google Drive limit)

### Performance Tips

1. **Use pagination for large lists**:
   ```bash
   ./gdrive_curl.sh list "" 50  # List 50 files at a time
   ```

2. **Parallel operations**:
   ```bash
   # Upload 4 files simultaneously
   ls *.pdf | xargs -P 4 -I {} ./gdrive_curl.sh upload {}
   ```

3. **Cache folder IDs**:
   ```bash
   # Store frequently used folder IDs
   REPORTS_FOLDER=$(./gdrive_curl.sh find-folder "Reports" | cut -f1)
   export REPORTS_FOLDER
   ```

## API Reference

### Google Drive Query Syntax

| Query | Description |
|-------|------------|
| `name = 'exact-name'` | Exact name match |
| `name contains 'text'` | Name contains text |
| `mimeType = 'type'` | Specific MIME type |
| `modifiedTime > '2024-01-01'` | Modified after date |
| `'parent_id' in parents` | Files in specific folder |
| `starred = true` | Starred files |
| `trashed = false` | Not in trash |
| `sharedWithMe = true` | Shared with you |

Combine with: `and`, `or`, `not`

### Export Formats

**Google Docs**:
- `pdf` - PDF Document
- `docx` - Microsoft Word
- `txt` - Plain Text
- `html` - Web Page
- `rtf` - Rich Text
- `odt` - OpenDocument

**Google Sheets**:
- `xlsx` - Microsoft Excel
- `csv` - Comma-Separated Values
- `pdf` - PDF Document
- `ods` - OpenDocument
- `tsv` - Tab-Separated Values

**Google Slides**:
- `pptx` - Microsoft PowerPoint
- `pdf` - PDF Document
- `odp` - OpenDocument

### Permission Roles

- `reader` - View only
- `writer` - Edit access
- `commenter` - Comment only
- `owner` - Full control (transfer ownership)

## Testing

Run the test suite:

```bash
cd tests
./run_tests.sh
```

Run specific tests:
```bash
./test_auth.sh
./test_file_ops.sh
./test_permissions.sh
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new features
4. Ensure all tests pass
5. Submit a pull request

## Security Considerations

- **Token Storage**: Tokens are stored in `~/.config/gdrive-curl/tokens.json`
  ```bash
  chmod 600 ~/.config/gdrive-curl/tokens.json
  ```

- **Credentials**: Never commit CLIENT_ID/CLIENT_SECRET to version control

- **Scope Limitation**: Use minimal required scope:
  ```bash
  # Full access (default)
  export SCOPE="https://www.googleapis.com/auth/drive"

  # Only app-created files
  export SCOPE="https://www.googleapis.com/auth/drive.file"
  ```

## License

MIT License - See [LICENSE](LICENSE) file for details

## Acknowledgments

- Built with Google Drive API v3
- OAuth 2.0 Device Flow (RFC 8628)
- Inspired by Unix philosophy: Do one thing well

## Links

- [Google Drive API Documentation](https://developers.google.com/drive/api/v3/reference)
- [OAuth 2.0 Device Flow](https://developers.google.com/identity/protocols/oauth2/limited-input-device)
- [Google Cloud Console](https://console.cloud.google.com/)

---

**Note**: This is an unofficial tool. Not affiliated with Google.
