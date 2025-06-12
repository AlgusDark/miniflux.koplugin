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
- **api.lua**: Miniflux API client handling HTTP requests
- **settings/**: Modular settings management system
- **miniflux_ui.lua**: User interface components and dialogs
- **browser/main_browser.lua**: Single browser implementation following OPDS pattern
- **browser/lib/base_browser.lua**: Base browser class with navigation logic
- **browser/lib/browser_utils.lua**: Utility functions for browser operations
- **lib/debug.lua**: Debug logging functionality
- **_meta.lua**: Plugin metadata

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