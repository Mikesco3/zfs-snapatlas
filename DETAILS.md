# ZFS Snapshot Atlas - Detailed Information

This document provides additional details, examples, and background information for ZFS Snapshot Atlas. For a quick start, please see the main [README.md](README.md).

## What It Does

ZFS Snapshot Atlas analyzes your ZFS snapshots and groups them into manageable chunks, then calculates how much space each chunk is consuming. It provides two main modes:

- **Chunk Mode (default)**: Shows the reclaimable space *if you were to delete an entire chunk of snapshots* (i.e., the space that would be freed by removing all snapshots in that chunk).
  - *Note:* "Chunk Mode" does **not** refer to the space between chunks, but rather the space that would be reclaimed by deleting the snapshots *within* each chunk.
- **To-Latest Mode**: Shows reclaimable space from each chunk to the most recent snapshot

The script can also delete specific chunks or sub-chunks, making it easy to reclaim storage without losing all your snapshots.

## Features

- 🔍 **Storage Analysis**: See exactly how much space each chunk of snapshots is consuming
- 🎯 **Targeted Deletion**: Delete specific chunks or sub-chunks instead of all snapshots
- 📊 **Flexible Chunking**: Divide snapshots into N chunks or use fixed chunk sizes
- 🛡️ **Safe Operations**: Dry-run mode by default with confirmation prompts for deletions
- 🔧 **Debug Mode**: Verbose output for troubleshooting and understanding

## Additional Usage Examples

### Basic Analysis

**Analyze snapshots with default chunk size (10):**
```bash
./zfs-snapatlas.sh rpool/data/vm-180-disk-0
```

**Analyze with custom chunk size:**
```bash
./zfs-snapatlas.sh rpool/data/vm-180-disk-0 5
```

**Verbose output for debugging:**
```bash
./zfs-snapatlas.sh -v rpool/data/vm-180-disk-0 10
```

### Chunking Strategies

**Divide snapshots into exactly 3 chunks:**
```bash
./zfs-snapatlas.sh -d 3 rpool/data/vm-180-disk-0
```

**Divide into 4 chunks with verbose output:**
```bash
./zfs-snapatlas.sh -v -d 4 rpool/data/vm-180-disk-0
```

### Analysis Modes

**Chunk mode (default) - shows reclaimable space by deleting snapshots within each chunk:**
```bash
./zfs-snapatlas.sh rpool/data/vm-180-disk-0 10
```

**To-latest mode - shows space from each chunk to most recent:**
```bash
./zfs-snapatlas.sh -l rpool/data/vm-180-disk-0 10
```

### Sub-Chunk Analysis

**Analyze only chunk 4, divided into sub-chunks of 1 snapshot each:**
```bash
./zfs-snapatlas.sh -d 4 -t 4,1 rpool/data/vm-180-disk-0
```

**Analyze chunk 4 with sub-chunks of 2 snapshots each in to-latest mode:**
```bash
./zfs-snapatlas.sh -l -d 4 -t 4,2 rpool/data/vm-180-disk-0
```

### Deletion Operations

**Delete chunk 1 (with confirmation):**
```bash
./zfs-snapatlas.sh -D 1 rpool/data/vm-180-disk-0
```

**Delete chunk 1 without confirmation:**
```bash
./zfs-snapatlas.sh -y -D 1 rpool/data/vm-180-disk-0
```

**Delete sub-chunk 3 of chunk 1 (requires -t flag):**
```bash
./zfs-snapatlas.sh -t 1,5 -D 1,3 rpool/data/vm-180-disk-0
```

**Delete ALL snapshots (with strong warnings):**
```bash
./zfs-snapatlas.sh --delete-all rpool/data/vm-180-disk-0
```

## Output Format

The script outputs a summary table showing:
- Chunk number
- Snapshot range (indices)
- First snapshot name
- Reclaimable space

Example output:
```
Most recent snapshot: auto-2025-01-15_12:00:00

=== SUMMARY: Chunk reclaim sizes (chunk mode: reclaim space per chunk) ===
chunk 01	[00-09]	auto-2025-01-01_12:00:00                    	1.2G
chunk 02	[10-19]	auto-2025-01-05_12:00:00                    	856M
chunk 03	[20-29]	auto-2025-01-10_12:00:00                    	2.1G
```

## Roadmap

- [ ] Improve error handling and edge case detection
- [ ] Add more flexible chunking strategies (e.g., by date, size, or custom rules)
- [ ] Support for more advanced deletion patterns (e.g., keep every Nth snapshot)
- [ ] Refactor code for modularity and easier testing
- [ ] Add unit and integration tests
- [ ] Write more comprehensive documentation and usage examples
- [ ] Package for easier installation (e.g., as a Homebrew or Debian package)
- [ ] Eventually: Turn this into a TUI (Text User Interface) using `dialog` or similar tools for selecting the zfs dataset against which to run it and interactive snapshot management (something similar or inspired off of `ncdu`)

## The Problem & Story

I fell in love with ZFS and snapshotting, but over time discovered that I was having issues figuring out where the storage was being taken up by snapshots. Usually, I'd be trying to zero in on the issue because something alerted me that the drive was becoming too full.

Initially, I'd take a scorched earth approach and delete almost all of my snapshots because the usual `zfs list -r -t snap` would never really show me the full picture. That was until I stumbled across an obscure mention of `zfs destroy -nv dataset@oldsnapshot%newersnapshot` and how that would give me an idea of the space that could be reclaimed by deleting everything between those two snapshots.

After looking for such a tool and not finding one, I finally decided to build it myself. Fortunately, AI came to the rescue to help me with the heavy lifting.

Please forgive me if this script isn't quite as good as it would be if it was written by someone with years of ZFS and bash coding experience, but it's the best I could do. This took me about three days and a few late nights of banging my head against the wall with the help (and sometimes against the help) of AI. Huge thanks to Cursor. While this script was developed with the help of multiple AI assistants, including Anthropic's Claude and OpenAI's ChatGPT, I found Google's Gemini Pro to be significantly more precise.

## Contributing

This script was created to solve a real problem I faced with ZFS snapshot management. If you find bugs or have improvements, please feel free to contribute!
