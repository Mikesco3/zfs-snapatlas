# ZFS Snapshot Atlas

A tool for analyzing and managing ZFS storage usage by chunks of snapshots. This script helps you understand where your storage is being consumed by snapshots and provides targeted deletion capabilities.

For more detailed information, see [DETAILS.md](DETAILS.md).

## Versioning

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Git tags are used to mark releases.

- **Current Version:** 0.2.5 (BETA)

## ⚠️ Beta Version Disclaimer

This tool is currently in **BETA** and should be used with caution, especially the deletion functionality. Please:

- **Test carefully** on non-critical datasets first
- **Report any issues** you encounter
- **Don't fully trust it yet** - always verify before running deletion operations
- **Backup important data** before using deletion features
- **Use debug mode** (`-v` flag) to preview operations before executing them

The deletion logic is particularly sensitive and may have edge cases that haven't been fully tested. Use at your own risk.

## Installation

### Short method
Run the following with root privileges command to download the script:
```bash
sudo wget -O /usr/bin/zfs-snapatlas https://raw.githubusercontent.com/Mikesco3/zfs-snapatlas/main/zfs-snapatlas.sh && sudo chmod +x /usr/bin/zfs-snapatlas
```

## Alternative: TUI Version

If you prefer a graphical terminal interface, there's also a **Terminal User Interface (TUI)** version available at [zfs-snapatlas-tui](https://github.com/Mikesco3/zfs-snapatlas-tui). 

⚠️ **Important**: The TUI version is currently in **BETA** (version 0.1.2) and should be tested carefully on non-critical datasets before use. The TUI version provides the same functionality as this CLI version but with an interactive dialog-based interface.

## Quick Start: Reclaim ZFS Snapshot Space in 4 Steps

Is your ZFS pool filling up unexpectedly? Old snapshots are often the culprit. This guide walks you through using `zfs-snapatlas` to find which snapshots are consuming the most space and how to safely remove them.

### Step 1: Find the Dataset with High Snapshot Usage

First, let's identify which ZFS dataset is using the most storage for snapshots.

Run this command to see a breakdown of space usage:
```sh
zfs list -o space
```

Look for datasets with a high value in the `USEDSNAP` column. In this example, `rpool/data/vm-180-disk-0` is using `34.3G` for snapshots, making it a good candidate for cleanup.

```
NAME                            AVAIL  USED   USEDSNAP  USEDDS  USEDREFRESERV  USEDCHILD
...
rpool/data/vm-180-disk-0        977G  61.5G     34.3G   27.2G             0B         0B
...
```

### Step 2: Get a High-Level "Atlas" of Your Snapshots

Now, let's get a high-level view of where that space is going. The script groups your snapshots into "chunks" (groups of 10 by default) and estimates the space you would **reclaim** by deleting each chunk.

Run the script on your target dataset:
```sh
./zfs-snapatlas.sh rpool/data/vm-180-disk-0
```

**What the output means:**
*   `chunk 1`: A group of the 10 oldest snapshots.
*   `[00-09]`: The snapshot index numbers in this chunk.
*   `34.3G`: The estimated space you would get back if you deleted these 10 snapshots.

```
Analyzing snapshots for dataset: rpool/data/vm-180-disk-0
Chunk size: 10

=== SUMMARY: Chunk reclaim sizes ===
chunk 1	[00-09]	20240902_before-Upgrades                  	34.3G
chunk 2	[10-19]	autosnap_2025-08-12_05:00:49_hourly         	0B
chunk 3	[20-29]	autosnap_2025-08-12_15:00:52_hourly         	0B
...
```
In this case, the oldest chunk of 10 snapshots is holding onto `34.3G` of data. The other chunks aren't holding any unique data. Let's investigate `chunk 1`.

> **Tip:** You can change the chunk size. For example, to use chunks of 5 snapshots:
> `./zfs-snapatlas.sh rpool/data/vm-180-disk-0 5`

### Step 3: Drill Down into a Problematic Chunk

The first chunk contains `34.3G` of reclaimable space. To get more detail, we can break it down into smaller **sub-chunks**.

Let's analyze `chunk 1` by breaking it into sub-chunks of 2 snapshots each. Use the `-t <chunk_number>,<sub_chunk_size>` flag:

```sh
./zfs-snapatlas.sh rpool/data/vm-180-disk-0 -t 1,2
```

The output now shows that `sub-chunk 1-1` (the first sub-chunk of chunk 1) is the one holding almost all the data.

```
Operating on chunk 1 [0-9] with 10 snapshots
Processing with sub-chunk size: 2 snapshots (5 sub-chunks)

=== SUMMARY: Sub-chunk reclaim sizes (from chunk 1) ===
sub-chunk 1-1	[00-01]	20240902_beforeUpgradingMint                	34.3G
sub-chunk 1-2	[02-03]	autosnap_2025-02-07_00:00:24_daily          	48K
sub-chunk 1-3	[04-05]	autosnap_2025-06-25_18:06:42_daily          	32K
...
```

### Step 4: Safely Delete Snapshots and Reclaim Space

Now that we've pinpointed the two snapshots consuming space, we can delete them.

To delete a specific sub-chunk, use the `-D <chunk>,<sub-chunk>` flag. This command targets `sub-chunk 1-1` for deletion.

```sh
./zfs-snapatlas.sh rpool/data/vm-180-disk-0 -t 1,2 -D 1,1
```

The script will always ask for confirmation before deleting anything. It shows you exactly which snapshots will be removed and how much space you'll reclaim.

```
🗑️  DELETE CONFIRMATION
========================
Sub-Chunk:      1-1
Reclaim space:  34.3G

Snapshots to delete:
  - 20240902_beforeUpgradingMint

Are you sure you want to delete these snapshots? (y/N):
```

Type `y` and press Enter to delete the snapshots and free up your storage.

> **Pro-Tip:** Use the `-v` flag for verbose output to see the exact `zfs` commands the script is running. Always double-check the deletion plan before confirming!

> **⚠️ Important: Chunk Re-Alignment After Deletion**
> After you delete a chunk, the script re-calculates the chunks on the next run. If you delete `chunk 1`, the old `chunk 2` will become the new `chunk 1`.
>
> **Always run a fresh analysis before each deletion** to ensure you are targeting the correct snapshots. Do not rely on chunk numbers from previous runs.

___

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


## License

GPLv3 - See LICENSE file for details.

## Contributing

This script was created to solve a real problem I faced with ZFS snapshot management. If you find bugs or have improvements, please feel free to contribute!

## Author

Michael Schmitz - Created with help from AI assistants (Cursor + Gemini Pro)


