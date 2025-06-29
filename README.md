# Miniflux Plugin for KOReader

This plugin provides integration with [Miniflux](https://miniflux.app/), a minimalist RSS reader, allowing you to read your RSS entries directly in KOReader.

## Features

- ✅ **Read Entries**: Fetch and read entries from your Miniflux server
- ✅ **Browse by Categories/Feeds**: Navigate through your feed categories and individual feeds
- ✅ **Fetch Options**: Customize entry limits, sorting order, and direction
- ✅ **Read/Unread Toggle**: Show only unread entries or all entries with visual indicators
- ✅ **Entry Management**: Mark entries as read/unread and toggle bookmarks

## Server Compatibility

The plugin is compatible with:
- ✅ **Miniflux v2.0.34+** (recommended)
- ⚠️ **Earlier versions**: Basic functionality may work but some features may be limited

Make sure your Miniflux server allows API access and you have valid credentials.

## Authentication

The plugin supports username/password authentication. API tokens are not currently supported but may be added in future versions.

## Usage

### Reading Entries

1. Go to **Tools > Miniflux > Read entries**
2. Entries will be fetched from your server based on your configured settings
3. Tap on any entry to read it
4. Use the buttons in the entry viewer to:
   - Mark as read/unread
   - Toggle bookmark
   - Close the entry

## Configuration

Available settings:

- **Entries limit**: Set the number of entries to fetch (default: 100)
- **Sort order**: Choose how to sort entries:
  - `published_at` - Sort by publish date (default)
  - `created_at` - Sort by creation date  
  - `id` - Sort by entry ID
- **Sort direction**: `desc` (newest first, default) or `asc` (oldest first)
- **Hide read entries**: When enabled, only show unread entries (default: enabled)
- **Auto mark read**: Automatically mark entries as read when opened (default: disabled)

## API Integration

The plugin uses the Miniflux API v1 with these endpoints:

- `GET /v1/entries` - Fetch entries with filtering options
- `PUT /v1/entries` - Update entry status (read/unread)
- `PUT /v1/entries/{id}/bookmark` - Toggle entry bookmark
- `GET /v1/feeds` - Get feeds list
- `GET /v1/categories` - Get categories list
- `GET /v1/feeds/{id}/entries` - Get entries for specific feed
- `GET /v1/categories/{id}/entries` - Get entries for specific category

## Interface

### Navigation

The plugin provides a hierarchical navigation system:

1. **Main Menu**: Choose between "Unread Entries", "Feeds", or "Categories"
2. **Feeds/Categories List**: Browse your organized content
3. **Entry List**: View and select entries to read
4. **Entry Viewer**: Read individual entries with management options

### Visual Indicators

- **Title Bar**: Shows current location in hierarchy
- **Status Icons**: 
  - `⊘` = Showing only unread entries
  - `◯` = Showing all entries (read + unread)
- **Entry Status**: 
  - `●` = Unread entry
  - `○` = Read entry

### Header Information

- **Title**: Shows the current section name (e.g., "Feeds", "Categories", "All Entries")
- **Subtitle**: Shows count information and status (e.g., "15 feeds", "25 unread entries", "10 unread / 5 read")

## Error Handling

Common issues and solutions:

- **Connection Failed**: Check your server URL, username, and password
- **API Token Invalid**: Make sure your credentials are correct and have API access
- **Server Error**: Check your Miniflux server logs for issues
- **Timeout**: Your server might be slow or overloaded

## Troubleshooting

- **Slow Loading**: Try reducing the entries limit in settings
- **Missing Entries**: Check if "Hide read entries" is enabled and you're looking for read entries
- **No Entries Found**: Check if you have any unread entries in Miniflux
- **Authentication Issues**: Verify your server URL format (include http:// or https://)

## Data Flow

1. Plugin authenticates with your Miniflux server
2. Fetches entries based on your filter settings
3. Displays entries in a browsable list
4. When you select an entry, it's displayed in KOReader's text viewer
5. Entry status changes are synced back to your Miniflux server

## Privacy

- The plugin only communicates with your configured Miniflux server
- No data is sent to third parties
- Your login credentials are stored locally on your device

## Setup

1. **Enable the Plugin**: Go to KOReader settings and enable the Miniflux plugin
2. **Configure Server**: 
   - Go to **Tools > Miniflux > Settings > Server address**
   - Enter your Miniflux server URL (e.g., `https://miniflux.example.com`)
   - Enter your API token (generate one in Miniflux: Settings > API Keys > Create a new API key)
3. **Test Connection**: Use **Tools > Miniflux > Settings > Test connection** to verify your setup

## Usage

### Reading Entries

1. Go to **Tools > Miniflux > Read entries**
2. Entries will be fetched from your server based on your configured settings
3. Tap on any entry to read it
4. Use the buttons in the entry viewer to:
   - Mark as read/unread
   - Toggle bookmark
   - Close the entry

### Configuring Fetch Options

Go to **Tools > Miniflux > Settings** to configure:

- **Entries limit**: Set the number of entries to fetch (default: 100)
- **Sort order**: Choose how to sort entries:
  - `published_at` - Sort by publish date (default)
  - `created_at` - Sort by creation date  
  - `id` - Sort by entry ID
- **Sort direction**: `desc` (newest first, default) or `asc` (oldest first)
- **Hide read entries**: When enabled, only show unread entries (default: enabled)
- **Auto mark read**: Automatically mark entries as read when opened (default: disabled)

## API Integration

This plugin uses the [Miniflux REST API](https://miniflux.app/docs/api.html) with the following endpoints:

- `GET /v1/me` - Test connection and get user info
- `GET /v1/entries` - Fetch entries with filtering options
- `PUT /v1/entries` - Update entry status (read/unread)
- `PUT /v1/entries/{id}/bookmark` - Toggle entry bookmark

## Module Structure

The plugin is organized into separate modules for maintainability:

- **main.lua**: Main plugin interface and menu integration
- **_meta.lua**: Plugin metadata
- **api/**: Modular API client system
- **settings/**: Modular settings management system with UI dialogs
- **browser/**: Modular browser system with screens, features, and utilities
- **typedefs/**: EmmyLua type definitions for KOReader integration

### Clean Root Directory
Only essential files remain at the plugin root:
- **main.lua**: Plugin entry point and coordination
- **_meta.lua**: Plugin metadata and identification

## Browser Navigation

The browser follows the same pattern as KOReader's OPDS browser:
- **Single Browser Instance**: Uses one browser that updates its content rather than creating multiple instances
- **Navigation History**: Maintains a navigation stack for proper back/forward functionality
- **Home Button**: The home button (house icon) closes the browser and returns to the main KOReader interface
- **Title and Subtitle**: Uses clean title with informational subtitle (e.g., "Feeds" with "15 feeds" subtitle)

### Interface Elements
- **Title**: Shows the current section name (e.g., "Feeds", "Categories", "All Entries")
- **Subtitle**: Shows count information and status (e.g., "15 feeds", "25 unread entries", "10 unread / 5 read")
- **Back Arrow**: Returns to the previous navigation level
- **Home Button**: Closes the browser entirely

## Authentication

The plugin uses API token authentication (recommended by Miniflux) via the `X-Auth-Token` header. Generate your API token in Miniflux under Settings > API Keys.

## Requirements

- Active Miniflux server instance
- Valid API token
- Network connectivity

## Troubleshooting

- **Connection Failed**: Verify server URL and API token
- **No Entries Found**: Check if you have any unread entries in Miniflux
- **Settings Not Saved**: Check KOReader settings directory permissions

## License

This plugin follows the same license as KOReader.

---

## Local Development & Building

This project uses [Task](https://taskfile.dev/) for managing local development tasks, such as building the plugin for testing.

### Prerequisites

1.  **Lua 5.3**: Ensure Lua 5.3 (including `luac5.3` for syntax checking) is installed and available in your system's PATH.
2.  **Task**: Install Task by following the instructions on the [official Task installation page](https://taskfile.dev/installation/).
3.  **Git**: Required for `Task` to clone LuaSrcDiet.
4.  **Make**: Required by LuaSrcDiet's build process.

### Building the Plugin Locally

The `Taskfile.yml` in the root of this repository defines the available tasks.

1.  **Install LuaSrcDiet (if not already done by Task):**
    The first time you run a build task, `Task` will automatically attempt to download and build `luasrcdiet` into a local `luasrcdiet_tool` directory. This requires `git` and `make` to be installed.

2.  **Available Task Commands:**

    *   `task` or `task default` or `task minify`:
        This is the default command. It will:
        *   Ensure LuaSrcDiet is available.
        *   Check the Lua syntax of all `.lua` files.
        *   Remove any existing `typedefs/` directories from the source (they are for linting/IDE only).
        *   Minify all `.lua` files from the project root (excluding build artifacts and tooling directories).
        *   Output the minified plugin structure to `dist/miniflux.koplugin/`.
        This `dist/miniflux.koplugin/` directory can then be copied to your KOReader `plugins/` directory for testing.

    *   `task check_lua_syntax`:
        Only runs the Lua syntax check using `luac5.3 -p` on the source files.

    *   `task clean`:
        Removes the `dist/` directory and any `*.zip` files from the project root. It also cleans the locally built LuaSrcDiet tool.

    *   `task --list-all` or `task -a`:
        Lists all available tasks defined in `Taskfile.yml`, including descriptions.

### Example Workflow

```bash
# To build the plugin for the first time (or after a clean)
task minify

# After making changes, to rebuild
task minify

# To clean up build artifacts
task clean
```
The output plugin will be located in the `dist/miniflux.koplugin` directory.

### CI Consistency
The Continuous Integration (CI) process executed via GitHub Actions also uses Taskfile (`task ci_minify`) to perform the minification. This ensures that the build process is consistent between local development and the automated CI environment. Developers primarily use the local tasks like `task minify`.
