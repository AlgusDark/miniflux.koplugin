# Miniflux Plugin for KOReader

A comprehensive RSS reader plugin that integrates Miniflux with KOReader, allowing you to read RSS entries offline on your e-reader device.

## Features

- Browse feeds, categories, and entries from your Miniflux server
- Download entries for offline reading with images
- Navigate between entries with context-aware next/previous
- Mark entries as read/unread
- Optimized for e-ink displays with efficient image downloading

## UX Improvements Roadmap

### Phase 1: Core Status Management
#### 1. Mark as Read/Unread Without Deletion
**Problem:** Currently, marking an entry requires keeping the local file or it disappears from navigation.  
**Solution:** Implement status-only updates that preserve downloaded entries locally.

**Features:**
- Update entry status via Miniflux API without deleting local HTML file
- Sync status changes with local DocSettings metadata
- Maintain entry navigation even after marking as read
- Visual indicators for read/unread status in local files

**User Benefit:** Keep valuable entries locally while managing read status properly.

---

### Phase 2: Storage Management
#### 2. Bulk Entry Deletion
**Problem:** Users need better control over storage space occupied by downloaded entries.  
**Solution:** Provide bulk deletion options for managing local storage.

**Features:**
- **Delete All Entries:** Remove all downloaded Miniflux entries and metadata
  - Confirmation dialog with storage space information
  - Progress indicator for deletion process
  - Option to exclude favorited/bookmarked entries
- **Delete by Date:** Remove entries older than specified timeframe
  - Configurable date ranges (1 week, 1 month, 3 months, 6 months)
  - Preview of entries to be deleted before confirmation

**User Benefit:** Easy storage management without manual file system navigation.

#### 3. Selective Image Management  
**Problem:** Images consume significant storage space; users want granular control.  
**Solution:** Advanced image management with storage optimization.

**Features:**
- **Delete All Images:** Remove images while preserving entry text
  - Scan all entry directories for image files
  - Show storage space to be freed before deletion
  - Update HTML to remove image references gracefully
- **Smart Image Cleanup:** Remove failed/broken image downloads
  - Detect corrupted or invalid image files
  - Remove orphaned images with no corresponding entries
- **Image Storage Statistics:** Display current image storage usage
  - Total images count and disk usage
  - Breakdown by entry/feed for detailed analysis

**User Benefit:** Optimize storage for text-focused reading while keeping images when needed.

---

### Phase 3: Advanced Download Features
#### 4. Intelligent Background Prefetching
**Problem:** Loading entries one-by-one creates waiting time during navigation.  
**Solution:** Smart background downloading based on reading patterns.

**Features:**
- **Configurable Prefetch Count:** Download N entries ahead (default: 1, range: 0-5)
  - Setting: "Download ahead count" in main settings
  - Disable with 0 for bandwidth-conscious users
- **Context-Aware Prefetching:** Intelligent selection based on current context
  - In feed view: prefetch next entries from same feed
  - In category view: prefetch next entries from same category  
  - In global unread: prefetch next unread entries chronologically
- **Bandwidth Management:** Respect connection and data limits
  - Only prefetch on WiFi (configurable)
  - Pause prefetching during active downloads
  - Background priority (doesn't block current entry loading)
- **Smart Cancellation:** Cancel irrelevant prefetch operations
  - Cancel when user navigates away from current context
  - Stop prefetching when storage space is low

**Technical Implementation:**
- Queue-based background downloader with priority management
- Integration with existing Trapper cancellation system
- Storage monitoring to prevent disk space issues

**User Benefit:** Seamless reading experience with near-instantaneous entry loading.

#### 5. Image Recovery and Re-processing
**Problem:** Network issues cause incomplete downloads; users want to retry without re-downloading text.  
**Solution:** Smart image recovery with selective re-downloading.

**Features:**
- **Missing Image Detection:** Scan entries for failed/missing images
  - Analyze HTML for image references without local files
  - Detect corrupted image files (invalid format, wrong size)
  - Report statistics: X entries with missing images
- **Selective Image Re-download:** Targeted image recovery
  - Re-download only missing/failed images
  - Preserve existing successful downloads
  - Update HTML with newly downloaded images
- **Batch Image Recovery:** Process multiple entries efficiently
  - Queue-based processing with progress tracking
  - Cancel/resume support for large recovery operations
  - Settings integration: "Include images" preference respected
- **Enhanced HTML Regeneration:** Recreate entry HTML with complete images
  - Preserve all metadata and formatting
  - Update DocSettings with new image count
  - Maintain original entry structure and styling

**Technical Details:**
- Extend existing `Images.discoverImages()` for gap analysis
- Reuse `EntryDownloader` infrastructure for consistency
- Atomic operations: only update HTML after successful image downloads

**User Benefit:** Recover from network failures without losing work; complete entry downloads retroactively.

---

### Phase 4: Enhanced Reading Experience
#### 6. Reading Statistics and Progress
**Features:**
- Track reading time per entry and total session time
- Progress indicators for long entries
- Reading history with completion status
- Daily/weekly reading statistics

#### 7. Offline Search and Filtering
**Features:**  
- Full-text search within downloaded entries
- Filter by feed, category, date range, read status
- Bookmark/favorite system for important entries
- Tag system for personal organization

#### 8. Sync and Backup
**Features:**
- Export reading data and annotations
- Backup entry metadata and reading progress
- Sync reading status across multiple devices
- OPML import/export for feed management

---

## Implementation Priority

**Priority 1:** Mark as read/unread without deletion (high impact, medium effort)  
**Priority 2:** Bulk deletion operations (high impact, low effort)  
**Priority 3:** Selective image management (medium impact, medium effort)  
**Priority 4:** Background prefetching (high impact, high effort)  
**Priority 5:** Image recovery system (medium impact, medium effort)

Each phase is designed to be independently valuable while building toward a comprehensive offline RSS reading experience optimized for e-ink devices.
