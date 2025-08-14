# ZFS Snapshot Atlas

A tool for analyzing and managing ZFS storage usage by chunks of snapshots. This script helps you understand where your storage is being consumed by snapshots and provides targeted deletion capabilities.

## ⚠️ Beta Version Disclaimer

**Version: 20250814 (Beta)**

This tool is currently in **BETA** and should be used with caution, especially the deletion functionality. Please:

- **Test carefully** on non-critical datasets first
- **Report any issues** you encounter
- **Don't fully trust it yet** - always verify before running deletion operations
- **Backup important data** before using deletion features
- **Use debug mode** (`-v` flag) to preview operations before executing them

The deletion logic is particularly sensitive and may have edge cases that haven't been fully tested. Use at your own risk.

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

## Installation

### Short method
Run the following with root privileges command to download the script:
```bash
sudo wget -O /usr/bin/zfs-snapatlas https://raw.githubusercontent.com/Mikesco3/zfs-snapatlas/main/zfs-snapatlas.sh && sudo chmod +x /usr/bin/zfs-snapatlas
```

## Quick Start

1. **Find a ZFS dataset or zvol to analyze**

   List your available datasets and their snapshot usage:
   ```sh
   zfs list -o space
   ```
   Example output:
   ```
   NAME                            AVAIL  USED   USEDSNAP  USEDDS  USEDREFRESERV  USEDCHILD
   rpool                           977G   534G        0B    208K             0B       534G
   rpool/ROOT                      977G  9.13G        0B    192K             0B      9.13G
   rpool/ROOT/pve-1                977G  9.13G     3.97G   5.16G             0B         0B
   rpool/data/subvol-151-disk-0   36.7G  64.3G      983M   63.3G             0B         0B
   rpool/data/subvol-152-disk-0    977G  4.69G      955M   3.76G             0B         0B
   rpool/data/vm-180-disk-0        977G  61.5G     34.3G   27.2G             0B         0B
   rpool/data/vm-180-disk-1        977G  4.96G       16K   4.96G             0B         0B
   ```

2. **Analyze snapshot usage for a dataset**

   Run the script on a dataset (e.g., `rpool/data/vm-180-disk-0`):
   ```sh
   ./zfs-snapatlas.sh rpool/data/vm-180-disk-0
   ```
   Example output:
   ```
   Analyzing snapshots for dataset: rpool/data/vm-180-disk-0
   Chunk size: 10

   Most recent snapshot: autosnap_2025-08-14_06:00:52_hourly

   === SUMMARY: Chunk reclaim sizes (chunk mode: reclaim space per chunk) ===
   chunk 1	[00-09]	20240902_before-Upgrades                  	34.3G
   chunk 2	[10-19]	autosnap_2025-08-12_05:00:49_hourly         	0B
   chunk 3	[20-29]	autosnap_2025-08-12_15:00:52_hourly         	0B
   chunk 4	[30-39]	autosnap_2025-08-13_00:00:53_hourly         	0B
   chunk 5	[40-46]	autosnap_2025-08-14_00:00:53_hourly         	0B
   ```
   > **Note:** By default, the script analyzes 10 snapshots per chunk. To change the chunk size, add a number as the second argument (e.g., 5 snapshots per chunk):
   > ```sh
   > ./zfs-snapatlas.sh rpool/data/vm-180-disk-0 5
   > ```

3. **Drill into a specific chunk with sub-chunks**

   To analyze the first chunk in sub-chunks of 2 snapshots each:
   ```sh
   ./zfs-snapatlas.sh rpool/data/vm-180-disk-0 -t 1,2
   ```
   Example output:
   ```
   Analyzing snapshots for dataset: rpool/data/vm-180-disk-0
   Chunk size: 10

   Operating on chunk 1 [0-9] with 10 snapshots
   Processing with sub-chunk size: 2 snapshots (5 sub-chunks)

   Most recent snapshot: autosnap_2025-08-14_06:00:52_hourly

   === SUMMARY: Sub-chunk reclaim sizes (from chunk 1) (chunk mode: reclaim space per chunk) ===
   ⚠️  Note: Small chunks (with few snapshots) show less reliable totals
   sub-chunk 1-1	[00-01]	20240902_beforeUpgradingMint                	34.3G
   sub-chunk 1-2	[02-03]	autosnap_2025-02-07_00:00:24_daily          	48K
   sub-chunk 1-3	[04-05]	autosnap_2025-06-25_18:06:42_daily          	32K
   sub-chunk 1-4	[06-07]	autosnap_2025-08-11_20:14:57_monthly        	0B
   sub-chunk 1-5	[08-09]	autosnap_2025-08-12_00:00:51_daily          	0B
   ```
4. **Delete a specific sub-chunk of snapshots**

   If you would like to delete sub-chunk 3 of chunk 1, you could issue the following command:
   ```sh
   ./zfs-snapatlas.sh rpool/data/vm-180-disk-0 -t 1,2 -D 1,3
   ```
   This would produce a confirmation following the summary:
   ```
   🗑️  DELETE CONFIRMATION
   ========================
   Sub-Chunk:  1-3
   Reclaim space:   3.08G

   Snapshots to delete:
     - syncoid_pve1_2024-04-12:20:35:08-GMT-05:00
     - syncoid_pve0_2024-04-29:18:05:42-GMT-05:00

   Are you sure you want to delete these snapshots? (y/N): 
   ```

> **Tip:** Use `-v` for verbose/debug output, and always review the summary before deleting snapshots!

___

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

## Command Line Options

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Enable debug mode (verbose output) |
| `-l, --to-latest` | Calculate reclaim from each chunk to most recent snapshot |
| `-d N, --divide-by N` | Split snapshots into N chunks (overrides chunk_size) |
| `-t N,M, --target N,M` | Operate only on chunk N, with M snapshots per sub-chunk |
| `-D coords, --delete` | Delete snapshots. Coordinates are required (e.g., `-D 1` or `-D 1,3`) |
| `--delete-all` | Delete ALL snapshots from the dataset (use with caution) |
| `-y, --yes` | Skip confirmation prompts (use with `-D` or `--delete-all`) |
| `-h, --help` | Show help message |

## Important Notes

⚠️ **Small chunks may show unreliable totals** due to ZFS shared block accounting. Use larger chunks or `-l/--to-latest` mode for more accurate space calculations.

💡 **Tip**: Use larger chunks or `-l/--to-latest` mode for more accurate space calculations.

🗑️ **Delete**: Use `-D` with coordinates to target specific chunks (e.g., `-D 1` or `-D 1,3 -t 1,5`).

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

Current version: 20250814

## Author

Michael Schmitz - Created with help from AI assistants (Cursor + Claude)


