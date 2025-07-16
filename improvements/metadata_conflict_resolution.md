# Metadata Conflict Resolution Implementation

## Problem
When ReaderUI and subprocess both modify entry metadata, conflicts can occur:
1. ReaderUI loads document and caches metadata in memory
2. Subprocess modifies SDR file (e.g., auto-healing)
3. ReaderUI saves its cached (stale) metadata, overwriting subprocess changes

## Solution
Implemented timestamp-based conflict detection and resolution:

### 1. SDR Modification Tracking
- Added `checkSDRModification()` to detect when SDR files are modified
- Track `_sdr_read_time` in metadata to know when we last read from SDR
- Compare modification times to detect external changes

### 2. Conflict Detection Points
- **On Document Open**: `onReaderReady()` checks for conflicts and reloads if needed
- **Before Updates**: `updateEntryStatus()` checks if SDR was modified externally
- **During Metadata Load**: Option to track read time for future conflict detection

### 3. Resolution Strategy
- Priority: Miniflux API > Newer SDR > Database
- When conflict detected, reload from SDR before making changes
- Preserve ReaderUI-specific fields while updating from SDR
- Log all conflict resolutions for debugging

### 4. Implementation Details

#### Entry Entity Changes
- `loadMetadata()` - Added option to track SDR read time
- `updateMetadata()` - Added conflict detection before updates
- `updateEntryStatus()` - Integrated conflict checking
- `resolveMetadataConflict()` - New function to handle conflicts

#### Entry Service Changes  
- `onReaderReady()` - Check and resolve conflicts on document open
- `spawnUpdateStatus()` - Track read time when loading metadata

## Benefits
1. Prevents data loss from subprocess modifications
2. Maintains consistency between ReaderUI and SDR
3. Transparent to users - conflicts resolved automatically
4. Detailed logging for troubleshooting

## Future Enhancements
1. Add database fields to track sync timestamps
2. Implement three-way merge for non-conflicting changes
3. Add metrics to track conflict frequency
