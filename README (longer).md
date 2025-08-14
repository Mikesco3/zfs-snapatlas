# ZFS Snapshot Atlas

A tool for analyzing and managing ZFS storage usage by chunks of snapshots. This script helps you understand where your storage is being consumed by snapshots and provides targeted deletion capabilities.

## ⚠️ Beta Version Disclaimer

**Version: 20250813 (Beta)**

This tool is currently in **BETA** and should be used with caution, especially the deletion functionality. Please:

- **Test carefully** on non-critical datasets first
- **Report any issues** you encounter
- **Don't fully trust it yet** - always verify before running deletion operations
- **Backup important data** before using deletion features
- **Use debug mode** (`-v` flag) to preview operations before executing them

The deletion logic is particularly sensitive and may have edge cases that haven't been fully tested. Use at your own risk.

## What It Does

ZFS Snapshot Atlas analyzes your ZFS snapshots and groups them into manageable chunks, then calculates how much space each chunk is consuming. It provides two main modes:

- **Gap Mode (default)**: Shows the reclaimable space *if you were to delete an entire chunk of snapshots* (i.e., the space that would be freed by removing all snapshots in that chunk).
  - *Note:* "Gap Mode" does **not** refer to the space between chunks, but rather the space that would be reclaimed by deleting the snapshots *within* each chunk.
- **Till-Last Mode**: Shows reclaimable space from each chunk to the most recent snapshot

The script can also delete specific chunks or sub-chunks, making it easy to reclaim storage without losing all your snapshots.

## Features

- 🔍 **Storage Analysis**: See exactly how much space each chunk of snapshots is consuming
- 🎯 **Targeted Deletion**: Delete specific chunks or sub-chunks instead of all snapshots
- 📊 **Flexible Chunking**: Divide snapshots into N chunks or use fixed chunk sizes
- 🛡️ **Safe Operations**: Dry-run mode by default with confirmation prompts for deletions
- 🔧 **Debug Mode**: Verbose output for troubleshooting and understanding

## Installation

### Short method
Run the following with root privileges command to download the script:
```bash
sudo wget -O /usr/bin/zfs-snapatlas https://raw.githubusercontent.com/Mikesco3/zfs-snapatlas/main/zfs-snapatlas.sh && sudo chmod +x /usr/bin/zfs-snapatlas
```

### Longer method
1. Clone this repository:
   ```bash
   git clone https://github.com/Mikesco3/zfs-snapatlas.git
   cd zfs-snapatlas
   ```

2. Make the script executable:
   ```bash
   chmod +x zfs-snapatlas.sh
   ```

3. (Optional) Copy it to the system path:
   ```bash
   sudo cp zfs-snapatlas.sh /usr/bin/zfs-snapatlas
   ```

4. Run it:
   ```bash
   zfs-snapatlas <dataset>
   ```

## Usage Examples

### Basic Analysis

**Analyze snapshots with default chunk size (10):**
```bash
./zfs-snapatlas.sh rpool/data/vm-180-disk-1
```

**Analyze with custom chunk size:**
```bash
./zfs-snapatlas.sh rpool/data/vm-180-disk-1 5
```

**Verbose output for debugging:**
```bash
./zfs-snapatlas.sh -v rpool/data/vm-180-disk-1 10
```

### Chunking Strategies

**Divide snapshots into exactly 3 chunks:**
```bash
./zfs-snapatlas.sh -d 3 rpool/data/vm-180-disk-1
```

**Divide into 4 chunks with verbose output:**
```bash
./zfs-snapatlas.sh -v -d 4 rpool/data/vm-180-disk-1
```

### Analysis Modes

**Gap mode (default) - shows reclaimable space by deleting snapshots within each chunk:**
```bash
./zfs-snapatlas.sh rpool/data/vm-180-disk-1 10
```

**Till-last mode - shows space from each chunk to most recent:**
```bash
./zfs-snapatlas.sh -t rpool/data/vm-180-disk-1 10
```

### Sub-Chunk Analysis

**Analyze only chunk 4, divided into sub-chunks of 1 snapshot each:**
```bash
./zfs-snapatlas.sh -d 4 -c 4,1 rpool/data/vm-180-disk-1
```

**Analyze chunk 4 with sub-chunks of 2 snapshots each:**
```bash
./zfs-snapatlas.sh -t -d 4 -c 4,2 rpool/data/vm-180-disk-1
```

### Deletion Operations

**Delete chunk 1 (with confirmation):**
```bash
./zfs-snapatlas.sh -D 1 rpool/data/vm-180-disk-1
```

**Delete chunk 1 without confirmation:**
```bash
./zfs-snapatlas.sh -Dy 1 rpool/data/vm-180-disk-1
```

**Delete sub-chunk 3 of chunk 1 (requires -c flag):**
```bash
./zfs-snapatlas.sh -D 1,3 -c 1,5 rpool/data/vm-180-disk-1
```

**Delete ALL snapshots (with strong warnings):**
```bash
./zfs-snapatlas.sh -D rpool/data/vm-180-disk-1
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

=== SUMMARY: Chunk reclaim sizes (gap mode: reclaim space per chunk) ===
chunk 01	[00-09]	auto-2025-01-01_12:00:00                    	1.2G
chunk 02	[10-19]	auto-2025-01-05_12:00:00                    	856M
chunk 03	[20-29]	auto-2025-01-10_12:00:00                    	2.1G
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Enable debug mode (verbose output) |
| `-t, --till-last` | Calculate reclaim from each chunk to most recent snapshot |
| `-d N, --divide-by N` | Split snapshots into N chunks (overrides chunk_size) |
| `-c N,M, --chunk N,M` | Operate only on chunk N, with M snapshots per sub-chunk |
| `-D [coords], --delete` | Delete snapshots (instead of dry-run) |
| `-y, --yes` | Skip confirmation prompts (use with -D) |
| `-h, --help` | Show help message |

## Important Notes

⚠️ **Small chunks may show unreliable totals** due to ZFS shared block accounting. Use larger chunks or `-t/--till-last` mode for more accurate space calculations.

💡 **Tip**: Use larger chunks or `-t/--till-last` mode for more accurate space calculations.

🗑️ **Delete**: Use `-D` with coordinates to target specific chunks (e.g., `-D 1` or `-D 1,3 -c 1,5`).

## Requirements

- ZFS filesystem with snapshots
- Bash shell
- `zfs` command available
- `shred` command (optional, for secure temp file deletion)


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

Please forgive me if this script isn't quite as good as it would be if it was written by someone with years of ZFS and bash coding experience, but it's the best I could do. This took me about three days and a few late nights of banging my head against the wall with the help (and sometimes against the help) of AI. Huge thanks to Cursor and Anthropic for Claude!

## License

GPLv3 - See LICENSE file for details.

## Contributing

This script was created to solve a real problem I faced with ZFS snapshot management. If you find bugs or have improvements, please feel free to contribute!

## Version

Current version: 20250813

## Author

Michael Schmitz - Created with help from AI assistants (Cursor + Claude)


