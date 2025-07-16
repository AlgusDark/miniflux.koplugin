# SDR Conflict Resolution Design

This document describes the SDR (sidecar) metadata conflict resolution system implemented in the Miniflux plugin.

## Problem Statement

KOReader can have multiple ReaderUI instances across different processes/threads that may modify SDR files independently. This can lead to metadata conflicts when:

1. A subprocess modifies the SDR file (e.g., auto-healing metadata)
2. The main ReaderUI instance has cached metadata that becomes stale
3. Multiple ReaderUI instances are open for the same document

## Solution: Database-Based Tracking

We track SDR file modifications in the database to detect and resolve conflicts:

### Database Schema

```sql
CREATE TABLE entries (
    -- ... existing fields ...
    sdr_mod_time INTEGER,    -- Last known SDR file modification time
    last_read_time INTEGER   -- When we last read/synced with the SDR
);
```

### Conflict Detection Flow

1. **On Entry Save**: Record the SDR file's modification time
2. **On Entry Open**: Check if SDR was modified after our last read
3. **On Conflict**: Reload metadata from SDR (source of truth)

### Implementation Details

#### EntryDatabase Changes

- Added `sdr_mod_time` and `last_read_time` fields
- Added `updateSDRTracking()` method to update tracking fields
- Modified `queryById()` and `queryAll()` to include tracking fields

#### EntryEntity Changes

- `saveMetadata()`: Records SDR modification time after writing
- `updateEntryStatus()`: Updates SDR tracking when status changes
- `resolveMetadataConflict()`: Uses database tracking instead of in-memory state

### Code Example

```lua
-- Check for conflicts when opening an entry
function EntryEntity.resolveMetadataConflict(entry_id, doc_settings)
    -- Get tracking info from database
    local db_entry = EntryDatabase.queryById(entry_id)
    if not db_entry then
        return true
    end
    
    -- Check if SDR was modified after our last read
    local was_modified, sdr_mod_time = checkSDRModification(entry_id, db_entry.last_read_time)
    
    if was_modified then
        -- Reload from SDR and update tracking
        local fresh_metadata = EntryEntity.loadMetadata(entry_id)
        doc_settings:saveSetting('miniflux_entry', fresh_metadata)
        EntryDatabase.updateSDRTracking(entry_id, sdr_mod_time, os.time())
    end
end
```

## Benefits

1. **Reliable Conflict Detection**: Database persists tracking across app restarts
2. **Subprocess Safety**: Detects changes made by other processes
3. **Performance**: Only reloads metadata when necessary
4. **Simplicity**: No complex in-memory state management

## Testing Scenarios

1. Open entry in main app, modify in subprocess, return to main app
2. Multiple ReaderUI instances modifying the same entry
3. App restart with pending SDR conflicts
4. Concurrent status updates from different sources