# Miniflux Plugin for KOReader

A KOReader plugin allows you to read RSS entries online/offline on your e-reader device.

## Features

Browse your Miniflux server content directly from KOReader:

- **Online/Offline Reading**: Browse feeds, categories, and entries online or offline. You can download entries individually or in batch.
- **Context-Aware Navigation**: Navigate between entries with next/previous actions after finishing reading an entry.
- **Status Synchronization**: Mark entries as read/unread. Don't worry if you aren't online, the system will keep an eye on it and you can sync it later or the system will remind you when you go online again.
- **E-ink Optimized**: Efficient image downloading and display for e-readers. You can proxy the images to be transformed for e-ink optimization so you can resize them to fit your reader.

## Installation

1. Download the [latest release from this repository](https://github.com/AlgusDark/miniflux.koplugin/releases/latest)
2. Unzip and copy the **miniflux.koplugin** folder into KOReader's plugin folder
3. Activate the plugin

## Usage

1. **Setup**: Configure your Miniflux server URL and credentials in the settings
2. **Browse**: Access feeds, categories, and entries from the "read entries" menu
3. **Read**: Select an entry and it will start downloading it. The entry will be opened after successfully downloaded.
4. **Download**: Tap hold an entry to enter into selection mode and batch download entries.
5. **Sync**: Status changes sync automatically with your Miniflux server. If in offline mode, it will queue the status for the next time you are online.

## Development Status

### ✅ Core Features

- [x] **Feed and Category Browsing**
  - [x] List all feeds and categories from Miniflux server
  - [x] Navigate feed and category organization
- [x] **Entry Management**
  - [x] Browse entries by feed, category, or unreads
  - [x] Download entries with text and images for offline reading
  - [x] Context-aware navigation (next/previous within current view)
- [x] **Status Management**
  - [x] Mark entries as read/unread without deleting local files
  - [x] Auto-mark as read when opening entry
  - [x] Batch mark as read when offline
- [x] **Offline Support**
  - [x] Full offline reading of downloaded entries
  - [x] Local file management and organization

### 🚧 Storage Management

- [x] **Bulk Entry Deletion**
  - [x] Delete selected entries
  - [ ] Delete by date range (1 week, 1 month, 3 months, 6 months)
  - [ ] Storage space reporting and cleanup
- [ ] **Selective Image Management**
  - [ ] Delete all images while preserving entry text
  - [ ] Image storage statistics and usage breakdown

### 🔄 Background Operations

- [ ] **Intelligent Prefetching**
  - [ ] Configurable prefetch count (download N entries ahead)
- [ ] **Image Recovery**
  - [ ] Selective re-download of missing images only

### 📊 Enhanced Reading Experience

- [ ] **Search and Organization**
  - [ ] Full-text search
  - [ ] Starred entries

## Technical Details

### Architecture

- **Modular Design**: Separate services for API, entries, navigation, and storage
- **Error Handling**: Comprehensive error management with user-friendly messages
- **Offline-First**: Graceful degradation when server is unavailable
- **E-ink Optimized**: Efficient image processing and display for e-readers

## Development

### Nix Development Environment (Recommended)

This project provides a complete Nix flake for reproducible development:

```bash
# With direnv (automatic)
direnv allow

# Manual activation
nix develop

# Available tools: lua, selene, stylua, task
```

### Manual Setup

If not using Nix, install these tools manually:

```bash
# Install tools
cargo install stylua selene
```

### Code Quality Tools

- **StyLua**: Code formatter
- **Selene**: Static analysis and linting
- **LuaLS**: Type checking with LuaCATS annotations

### Quick Commands

```bash
# Check code quality
task check

# Auto-fix formatting
task fmt-fix
```

### Development Setup with KOReader

For development testing, create a symlink to the built plugin:

#### macOS

```bash
# Build the plugin first
task build

# Create symlink to KOReader plugins directory
ln -s /path/to/miniflux.koplugin/dist/miniflux.koplugin ~/.config/koreader/plugins/miniflux.koplugin

# Run KOReader with debug logging
/System/Volumes/Data/Applications/KOReader.app/Contents/MacOS/koreader -d

# Filter logs for Miniflux-specific messages
/System/Volumes/Data/Applications/KOReader.app/Contents/MacOS/koreader -d 2>&1 | grep -E "Miniflux"
```

## Contributing

Contributions are welcome! Please feel free to:

- Report bugs and suggest features
- Submit pull requests for improvements
- Help with testing on different devices
- Contribute to documentation
