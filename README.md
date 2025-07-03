# Miniflux Plugin for KOReader

A comprehensive RSS reader plugin that integrates Miniflux with KOReader, allowing you to read RSS entries offline on your e-reader device.

## Features

Browse your Miniflux server content directly from KOReader:
- **Offline Reading**: Download entries with images for offline access
- **Context-Aware Navigation**: Navigate between entries with intelligent next/previous
- **Feed Management**: Browse feeds, categories, and entries
- **Status Synchronization**: Mark entries as read/unread with server sync
- **E-ink Optimized**: Efficient image downloading and display for e-readers

## Installation

1. Download the plugin files to your KOReader plugins directory
2. Enable the plugin in KOReader's Plugin Manager
3. Configure your Miniflux server settings

## Usage

1. **Setup**: Configure your Miniflux server URL and credentials in plugin settings
2. **Browse**: Access feeds, categories, and entries from the plugin menu
3. **Download**: Select entries to download for offline reading
4. **Read**: Open downloaded entries with full offline access
5. **Sync**: Status changes sync automatically with your Miniflux server

## Development Status

### ✅ Core Features (Completed)
- [x] **Feed and Category Browsing**
  - [x] List all feeds and categories from Miniflux server
  - [x] Navigate feed hierarchies and category organization
- [x] **Entry Management**
  - [x] Browse entries by feed, category, or global unread
  - [x] Download entries with text and images for offline reading
  - [x] Context-aware navigation (next/previous within current view)
- [x] **Status Management**
  - [x] Mark entries as read/unread without deleting local files
  - [x] Auto-mark as read when opening entry
  - [ ] Batch mark as read when offline (TODO: queue status updates)
- [x] **Offline Support**
  - [x] Full offline reading of downloaded entries
  - [x] Fallback navigation when server is unavailable
  - [x] Local file management and organization

### 🚧 Storage Management (Planned)
- [ ] **Bulk Entry Deletion**
  - [ ] Delete all entries with confirmation dialog
  - [ ] Delete by date range (1 week, 1 month, 3 months, 6 months)
  - [ ] Storage space reporting and cleanup
- [ ] **Selective Image Management**
  - [ ] Delete all images while preserving entry text
  - [ ] Smart cleanup of failed/broken image downloads
  - [ ] Image storage statistics and usage breakdown
- [ ] **Advanced Cleanup**
  - [ ] Remove orphaned images with no corresponding entries
  - [ ] Detect and remove corrupted image files
  - [ ] Option to exclude favorited/bookmarked entries from deletion

### 🔄 Background Operations (Planned)
- [ ] **Intelligent Prefetching**
  - [ ] Configurable prefetch count (download N entries ahead)
  - [ ] Context-aware prefetching based on current browsing context
  - [ ] Bandwidth management (WiFi-only, pause during active downloads)
  - [ ] Smart cancellation when navigating away from context
- [ ] **Image Recovery**
  - [ ] Scan entries for missing/failed images
  - [ ] Selective re-download of missing images only
  - [ ] Batch image recovery with progress tracking
  - [ ] Enhanced HTML regeneration with complete images

### 📊 Enhanced Reading Experience (Future)
- [ ] **Reading Analytics**
  - [ ] Track reading time per entry and session
  - [ ] Progress indicators for long entries
  - [ ] Reading history with completion status
  - [ ] Daily/weekly reading statistics
- [ ] **Search and Organization**
  - [ ] Full-text search within downloaded entries
  - [ ] Filter by feed, category, date range, read status
  - [ ] Bookmark/favorite system for important entries
  - [ ] Personal tag system for organization
- [ ] **Sync and Backup**
  - [ ] Export reading data and annotations
  - [ ] Backup entry metadata and reading progress
  - [ ] Cross-device reading status synchronization
  - [ ] OPML import/export for feed management

## Technical Details

### Architecture
- **Modular Design**: Separate services for API, entries, navigation, and storage
- **Error Handling**: Comprehensive error management with user-friendly messages
- **Offline-First**: Graceful degradation when server is unavailable
- **E-ink Optimized**: Efficient image processing and display for e-readers

### Key Components
- **MinifluxAPI**: Server communication and data fetching
- **EntryService**: Entry downloading and management
- **NavigationService**: Context-aware entry navigation
- **Files Utilities**: File operations and storage management

## Contributing

Contributions are welcome! Please feel free to:
- Report bugs and suggest features
- Submit pull requests for improvements
- Help with testing on different devices
- Contribute to documentation

## License

This plugin is part of the KOReader project and follows the same licensing terms.
