#!/bin/bash
## This script attempts to helps find the storage being used by snapshots.
## License: GPLv3
## Copyright (C) 2025 Michael Schmitz
VERSION="0.2.0"
## Now supports: lists snapshots and their reclaim size per chunk, and deletes snapshots
## Pending:
##
## Note: This script requires ZFS snapshots to be present on the target system.
##       It can be developed/tested on a different computer, but actual execution
##       requires access to the ZFS filesystem with snapshots. 

# Script to analyze ZFS snapshot usage by chunks

# Default values
debug_mode=false
dataset=""
chunk_size=10
divide_by=0
target_spec=""
chunk_mode=true
chunk_to_latest_mode=false
delete_mode=false
delete_coordinates=""  # Format: "chunk" or "chunk,sub-chunk"
delete_all_mode=false
skip_confirmation=false

# Help function
usage() {
    echo "# Script to analyze ZFS snapshot usage by chunks"
    echo "# Note: This script requires ZFS snapshots to be present on the target system."
    echo "# version: $VERSION"
    echo "# Now supports: list chunks of snapshots and their reclaim size, and can delete snapshots"
    echo "#"
    echo "Usage: $0 [-v] [-l] [-d N] [-t N,M] [-D coords | --delete-all] [-y] <dataset> [chunk_size]"
    echo "Options:"
    echo "  -v, --verbose         Enable debug mode (verbose output)"
    echo "  -l, --to-latest       Calculate reclaim from each chunk to most recent snapshot"
    echo "  -d N, --divide-by N   Split snapshots into N chunks (overrides chunk_size)"
    echo "  -t N,M --target N,M   Operate only on chunk N, with M snapshots per sub-chunk"
    echo "      --delete-all      Delete ALL snapshots from the dataset (requires confirmation)"
    echo "  -D coords, --delete   Delete snapshots. Coordinates are required:"
    echo "                       chunk     = delete specific chunk (e.g., -D 1)"
    echo "                       chunk,sub = delete specific sub-chunk (requires -t)"
    echo "  -y, --yes             Skip confirmation prompts (use with -D or --delete-all)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Default behavior: Calculate reclaim by deleting snapshots within each chunk (chunk mode)."
    echo ""
    echo "Examples:"
    echo "  $0 rpool/data/vm-180-disk-1 5          # Analyze with chunk size 5"
    echo "  $0 -d 4 rpool/data/vm-180-disk-1       # Divide snapshots into 4 chunks"
    echo "  $0 -t 1,2 rpool/data/vm-180-disk-1     # Analyze chunk 1 with sub-chunk size 2"
    echo "  $0 -D 1 rpool/data/vm-180-disk-1       # Delete chunk 1"
    echo "  $0 --delete-all rpool/data/vm-180-disk-1 # Delete ALL snapshots"
    echo ""
    echo "⚠️  Note: Small chunks may show unreliable totals due to ZFS shared block accounting."
    echo "💡  Tip: Use larger chunks or -l/--to-latest mode for more accurate space calculations."
    echo "🗑️  Delete: Use -D with coordinates for specific chunks/sub-chunks, or --delete-all."
    echo "ℹ️  Chunk space is calculated from the first to the last snapshot within the chunk."
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            debug_mode=true
            shift
            ;;
        -l|--to-latest)
            chunk_to_latest_mode=true
            chunk_mode=false
            shift
            ;;
        -d|--divide-by)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ && "$2" -gt 0 ]]; then
                divide_by="$2"
                shift 2
            else
                echo "Error: -d/--divide-by requires a positive integer argument" >&2
                usage
                exit 1
            fi
            ;;
        -t|--target)
            if [[ -n "$2" && "$2" =~ ^[0-9]+,[0-9]+$ ]]; then
                target_spec="$2"
                shift 2
            else
                echo "Error: -t/--target requires format N,M (e.g., 4,1)" >&2
                usage
                exit 1
            fi
            ;;
        --delete-all)
            delete_all_mode=true
            delete_mode=true
            shift
            ;;
        -D|--delete)
            delete_mode=true
            # Check if an argument is provided for -D
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                delete_coordinates="$2"
                # Validate coordinates format
                if [[ "$delete_coordinates" =~ ^[0-9]+$ || "$delete_coordinates" =~ ^[0-9]+,[0-9]+$ ]]; then
                    shift 2
                else
                    echo "Error: Invalid delete coordinates format. Use: -D chunk or -D chunk,sub-chunk" >&2
                    exit 1
                fi
            else
                echo "Error: -D/--delete requires coordinates (e.g., -D 1). To delete all snapshots, use --delete-all." >&2
                exit 1
            fi
            ;;
        -y|--yes)
            skip_confirmation=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ -z "$dataset" ]]; then
                dataset="$1"
            elif [[ "$chunk_size" == "10" ]]; then
                chunk_size="$1"
            else
                echo "Error: Too many arguments" >&2
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if dataset argument is provided
if [[ -z "$dataset" ]]; then
    echo "Error: Dataset argument is required" >&2
    usage
    exit 1
fi

# Validate delete options
if [[ "$skip_confirmation" == true && "$delete_mode" == false ]]; then
    echo "Warning: -y/--yes specified without -D/--delete or --delete-all (ignoring -y)" >&2
    skip_confirmation=false
fi

# Validate delete coordinates with -t combinations
if [[ "$delete_mode" == true ]]; then
    if [[ -n "$target_spec" ]]; then
        # -t is present, must have chunk,sub-chunk coordinates
        if [[ ! "$delete_coordinates" =~ ^[0-9]+,[0-9]+$ ]]; then
            echo "Error: When using -t flag, -D must specify target coordinates (-D chunk,sub-chunk)" >&2
            exit 1
        fi
    elif [[ "$delete_coordinates" =~ ^[0-9]+,[0-9]+$ ]]; then
        # Have chunk,sub-chunk coordinates but no -t flag
        echo "Error: Sub-chunk coordinates (-D chunk,sub-chunk) require -t flag with chunk size" >&2
        exit 1
    fi
fi

# Validate chunk specification
if [[ -n "$target_spec" ]]; then
    # Parse chunk specification
    target_chunk="${target_spec%,*}"
    sub_chunks="${target_spec#*,}"
    
    if [[ "$sub_chunks" -lt 1 ]]; then
        echo "Error: Sub-chunk count must be at least 1" >&2
        exit 1
    fi
    
    if [[ "$target_chunk" -lt 1 ]]; then
        echo "Error: Chunk number must be at least 1" >&2
        exit 1
    fi
fi

# Initialize target variables with safe defaults
target_chunk=""
sub_chunk_target=""
target_start=""
target_end=""
target_count=""
target_is_last_chunk=false
next_chunk_first_snap=""

# Extract target chunk number from delete coordinates if present
if [[ -n "$delete_coordinates" ]]; then
    target_chunk="${delete_coordinates%,*}"
    if [[ "$delete_coordinates" =~ ^[0-9]+,[0-9]+$ ]]; then
        sub_chunk_target="${delete_coordinates#*,}"
    fi
fi

# Extract target chunk number from chunk specification if present
if [[ -n "$target_spec" ]]; then
    target_chunk="${target_spec%,*}"
    sub_chunks="${target_spec#*,}"
fi

# Validate target_chunk is numeric if set
if [[ -n "$target_chunk" && ! "$target_chunk" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid target chunk number: $target_chunk" >&2
    exit 1
fi

# Validate sub_chunk_target is numeric if set
if [[ -n "$sub_chunk_target" && ! "$sub_chunk_target" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid sub-chunk target: $sub_chunk_target" >&2
    exit 1
fi

# Create temporary file for snapshots
snaps_temp_file=$(mktemp -t "pve_snap-usage.XXXXXXXXXX" 2>/dev/null) || {
    echo "Error: Failed to create temporary file" >&2
    exit 1
}

# Ensure the temp file has restrictive permissions
chmod 600 "$snaps_temp_file" 2>/dev/null

# Cleanup function to remove temp file
cleanup() {
    if [[ -n "$snaps_temp_file" && -f "$snaps_temp_file" ]]; then
        # Overwrite with zeros before deletion if shred is available
        if command -v shred >/dev/null 2>&1; then
            shred -u "$snaps_temp_file" 2>/dev/null || rm -f "$snaps_temp_file"
        else
            rm -f "$snaps_temp_file"
        fi
    fi
}
trap cleanup EXIT

# Function to get user confirmation for deletion
confirm_deletion() {
    local chunk_type="$1"
    local chunk_id="$2"
    local start_snap="$3"
    local end_snap="$4"
    local reclaim_size="$5"
    local snapshot_list="$6"  # Optional: list of snapshots to delete
    
    echo ""
    echo "🗑️  DELETE CONFIRMATION"
    echo "========================"
    
    if [[ "$chunk_type" == "all" ]]; then
        echo "⚠️  WARNING: You are about to delete ALL snapshots from dataset $dataset"
        echo "⚠️  This is a DESTRUCTIVE operation that cannot be undone!"
        echo "⚠️  To delete specific chunks instead, use: -D chunk_number"
        echo "⚠️  To delete specific sub-chunks, use: -D chunk,sub-chunk -t chunk,size"
        echo ""
        echo "Dataset: $dataset"
        echo "Total snapshots: $total_snapshots"
        echo "Reclaim space: $reclaim_size"
    elif [[ "$chunk_type" == "chunk" ]]; then
        echo "Chunk:  $chunk_id"
        echo "Start snapshot:  $start_snap"
        echo "End snapshot:    $end_snap"
        echo "Reclaim space:   $reclaim_size"
        
        # Show snapshot list if provided
        if [[ -n "$snapshot_list" ]]; then
            echo ""
            echo "Snapshots to delete:"
            echo "$snapshot_list" | while IFS= read -r snap; do
                [[ -n "$snap" ]] && echo "  - ${snap#*@}"
            done
        fi
    else
        echo "Sub-Chunk:  $chunk_id"
        echo "Start snapshot:  $start_snap"
        echo "Reclaim space:   $reclaim_size"
        
        # Show snapshot list if provided
        if [[ -n "$snapshot_list" ]]; then
            echo ""
            echo "Snapshots to delete:"
            echo "$snapshot_list" | while IFS= read -r snap; do
                [[ -n "$snap" ]] && echo "  - ${snap#*@}"
            done
        fi
    fi
    echo ""
    
    if [[ "$skip_confirmation" == true ]]; then
        echo "Auto-confirming deletion (--yes specified)"
        return 0
    fi
    
    read -p "Are you sure you want to delete these snapshots? (y/N): " -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        echo "Deletion cancelled."
        return 1
    fi
}

echo "Analyzing snapshots for dataset: $dataset"

# Get snapshots sorted by creation (oldest first), only names
zfs list -t snap -H -o name -s creation -r "$dataset" 2>/dev/null > "$snaps_temp_file" || {
    echo "Error: Failed to list snapshots for $dataset" >&2
    exit 1
}

# Check if we got any snapshots
if [[ ! -s "$snaps_temp_file" ]]; then
    echo "No snapshots found for dataset $dataset"
    exit 0
fi

total_snapshots=$(wc -l < "$snaps_temp_file")

# Calculate chunk size if divide-by is specified
if [[ $divide_by -gt 0 ]]; then
    chunk_size=$((total_snapshots / divide_by))
    if [[ $chunk_size -eq 0 ]]; then
        chunk_size=1
    fi
    echo "Dividing $total_snapshots snapshots into $divide_by chunks (chunk size: $chunk_size)"
else
    echo "Chunk size: $chunk_size"
fi

if [[ "$debug_mode" == true ]]; then
    echo "Debug mode: enabled"
fi
echo ""

if [[ "$debug_mode" == true ]]; then
    echo "Found snapshots:"
    head -10 "$snaps_temp_file"
    if [[ $total_snapshots -gt 10 ]]; then
        echo "..."
    fi
    echo ""
fi

# Test chunk creation with specified chunk size
if [[ "$debug_mode" == true ]]; then
    echo "Creating chunks with size $chunk_size:"
fi
chunks=""
chunk_start=0

# Read snapshots into array
snapshot_array=()
mapfile -t snapshot_array < "$snaps_temp_file"
original_snapshot_array=("${snapshot_array[@]}")
original_total_snapshots=$total_snapshots

# Get the most recent snapshot name (last line, strip everything before and including "@")
if [[ $total_snapshots -gt 0 ]]; then
    most_recent_snap_name="${snapshot_array[$((total_snapshots - 1))]#*@}"
    dataset_name="${snapshot_array[0]%@*}"
else
    echo "Error: No snapshots found" >&2
    exit 1
fi
if [[ "$debug_mode" == true ]]; then
    echo "Oldest snapshot: ${snapshot_array[0]}"
    echo "Most recent snapshot: ${snapshot_array[$((total_snapshots - 1))]}"
    echo "Most recent snapshot name: $most_recent_snap_name"
    echo "Dataset name: $dataset_name"
    echo ""
fi

# Handle plain -D (delete all snapshots) before chunk processing
if [[ "$delete_all_mode" == true ]]; then
    # Get reclaim size for all snapshots
    destroy_flags="-nv"
    if [[ "$delete_mode" == true ]]; then
        destroy_flags="-v"
        # Get reclaim size first for confirmation
        dry_run_output=$(zfs destroy -nv "$dataset@*" 2>&1)
        reclaim_size=$(echo "$dry_run_output" | grep "would reclaim" | awk '{print $NF}')
        if [[ -z "$reclaim_size" ]]; then
            reclaim_size="0B"
        fi
        # Confirm deletion of all snapshots
        if ! confirm_deletion "all" "" "" "" "$reclaim_size"; then
            echo "Deletion cancelled."
            exit 0
        fi
    fi
    destroy_output=$(zfs destroy $destroy_flags "$dataset@*" 2>&1)
    exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo "Successfully deleted all snapshots."
        exit 0
    else
        echo "Error deleting snapshots: $destroy_output" >&2
        exit 1
    fi
fi

# If chunk specification is provided, calculate original chunks and extract target chunk
if [[ -n "$target_spec" ]]; then
    # Calculate original chunk boundaries based on current mode
    original_chunks=()
    chunk_start=0
    chunk_num=1
    
    if [[ $divide_by -gt 0 ]]; then
        # Mode: -d N (divide into N chunks)
        original_divide_by=$divide_by
        
        while [[ "$chunk_start" -lt "$total_snapshots" && "$chunk_num" -le "$original_divide_by" ]]; do
            if [[ "$chunk_num" -eq "$original_divide_by" ]]; then
                chunk_end=$((total_snapshots - 1))
            else
                chunk_end=$((chunk_start + chunk_size - 1))
                if [[ "$chunk_end" -ge "$total_snapshots" ]]; then
                    chunk_end=$((total_snapshots - 1))
                fi
            fi
            
            original_chunks+=("$chunk_start:$chunk_end")
            chunk_start=$((chunk_end + 1))
            chunk_num=$((chunk_num + 1))
        done
        
        # Validate target chunk number
        if [[ "$target_chunk" -gt "$original_divide_by" ]]; then
            echo "Error: Chunk number must be between 1 and $original_divide_by" >&2
            exit 1
        fi
        original_total_chunks=$original_divide_by
    else
        # Mode: fixed chunk size
        original_chunk_size=$chunk_size
        
        while [[ "$chunk_start" -lt "$total_snapshots" ]]; do
            chunk_end=$((chunk_start + original_chunk_size - 1))
            if [[ "$chunk_end" -ge "$total_snapshots" ]]; then
                chunk_end=$((total_snapshots - 1))
            fi
            
            original_chunks+=("$chunk_start:$chunk_end")
            chunk_start=$((chunk_end + 1))
            chunk_num=$((chunk_num + 1))
        done
        
        # Validate target chunk number
        if [[ "$target_chunk" -gt "${#original_chunks[@]}" ]]; then
            echo "Error: Chunk number must be between 1 and ${#original_chunks[@]}" >&2
            exit 1
        fi
        original_total_chunks=${#original_chunks[@]}
    fi
    
    # Extract target chunk boundaries
    target_chunk_idx=$((target_chunk - 1))
    target_boundaries="${original_chunks[$target_chunk_idx]}"
    target_start="${target_boundaries%:*}"
    target_end="${target_boundaries#*:}"
    target_count=$((target_end - target_start + 1))
    
    # Determine if target chunk is the last chunk and get next chunk info
    target_is_last_chunk=false
    next_chunk_first_snap=""
    if [[ "$target_chunk" -eq "$original_total_chunks" ]]; then
        target_is_last_chunk=true
    else
        # Get first snapshot of the next chunk
        next_chunk_idx="$target_chunk"  # target_chunk is 1-based, so this gives us the next chunk
        next_chunk_boundaries="${original_chunks[$next_chunk_idx]}"
        next_chunk_start="${next_chunk_boundaries%:*}"
        next_chunk_first_snap="${snapshot_array[$next_chunk_start]}"
    fi
    
    if [[ "$debug_mode" == true ]]; then
        echo "Original chunks: ${original_chunks[*]}"
        echo "Target chunk $target_chunk: [$target_start-$target_end] ($target_count snapshots)"
        echo "Sub-chunk size: $sub_chunks snapshots"
        echo "Target is last chunk: $target_is_last_chunk"
        if [[ "$target_is_last_chunk" == false ]]; then
            echo "Next chunk first snap: $next_chunk_first_snap"
        fi
        echo ""
    fi
    
    # Set chunk_size to the requested sub-chunk size and calculate number of sub-chunks
    chunk_size=$sub_chunks
    divide_by=$((target_count / chunk_size))
    if [[ $((target_count % chunk_size)) -gt 0 ]]; then
        divide_by=$((divide_by + 1))  # Round up for remainder
    fi
    
    # Create new snapshot array with only target chunk snapshots
    temp_array=()
    for ((i=target_start; i<=target_end; i++)); do
        temp_array+=("${snapshot_array[$i]}")
    done
    snapshot_array=("${temp_array[@]}")
    total_snapshots=${#snapshot_array[@]}
    
    echo "Operating on chunk $target_chunk [$target_start-$target_end] with $target_count snapshots"
    echo "Processing with sub-chunk size: $chunk_size snapshots ($divide_by sub-chunks)"
    echo ""
fi

# Add these variables for better tracking
current_chunk_context=""  # Which original chunk we're processing
current_sub_chunk_num=0   # Current sub-chunk number within the context

# Add this validation after chunk processing setup
if [[ -n "$sub_chunk_target" ]]; then
    # Calculate how many sub-chunks exist
    if [[ -n "$target_spec" ]]; then
        total_sub_chunks="$divide_by"
    else
        # Need to calculate based on chunk size
        total_sub_chunks=$(( (total_snapshots + chunk_size - 1) / chunk_size ))
    fi
    
    if [[ "$sub_chunk_target" -gt "$total_sub_chunks" ]]; then
        echo "Error: Sub-chunk $sub_chunk_target doesn't exist. Only $total_sub_chunks sub-chunks available." >&2
        exit 1
    fi
    
    if [[ "$sub_chunk_target" -lt 1 ]]; then
        echo "Error: Sub-chunk number must be at least 1" >&2
        exit 1
    fi
fi

chunk_num=1

# This is the primary loop for snapshot chunk processing

while [[ "$chunk_start" -lt "$total_snapshots" && ("$divide_by" -eq 0 || "$chunk_num" -le "$divide_by") ]]; do
    # Update context tracking
    if [[ -n "$target_spec" ]]; then
        current_chunk_context="$target_chunk"
        current_sub_chunk_num="$chunk_num"
    else
        current_chunk_context="$chunk_num"
        current_sub_chunk_num=0  # Not in sub-chunk mode
    fi
    
    # Skip processing if we're only interested in a specific chunk and this isn't it
    if [[ -n "$delete_coordinates" && -z "$target_spec" && "$current_chunk_context" != "$target_chunk" ]]; then
        # Correctly calculate chunk_end before skipping
        if [[ "$divide_by" -gt 0 && "$chunk_num" -eq "$divide_by" ]]; then
            chunk_end=$((total_snapshots - 1))
        else
            chunk_end=$((chunk_start + chunk_size - 1))
            if [[ "$chunk_end" -ge "$total_snapshots" ]]; then
                chunk_end=$((total_snapshots - 1))
            fi
        fi
        chunk_start=$((chunk_end + 1))
        chunk_num=$((chunk_num + 1))
        continue
    fi
    
    # Skip processing if we're only interested in a specific sub-chunk and this isn't it
    if [[ -n "$sub_chunk_target" && "$current_sub_chunk_num" != "$sub_chunk_target" ]]; then
        # Calculate the chunk end to move past this sub-chunk
        if [[ "$divide_by" -gt 0 && "$chunk_num" -eq "$divide_by" ]]; then
            chunk_end=$((total_snapshots - 1))
        else
            chunk_end=$((chunk_start + chunk_size - 1))
            if [[ "$chunk_end" -ge "$total_snapshots" ]]; then
                chunk_end=$((total_snapshots - 1))
            fi
        fi
        chunk_start=$((chunk_end + 1))
        chunk_num=$((chunk_num + 1))
        continue
    fi
    # For the last chunk, include all remaining snapshots
    if [[ "$divide_by" -gt 0 && "$chunk_num" -eq "$divide_by" ]]; then
        chunk_end=$((total_snapshots - 1))
    else
        chunk_end=$((chunk_start + chunk_size - 1))
        if [[ "$chunk_end" -ge "$total_snapshots" ]]; then
            chunk_end=$((total_snapshots - 1))
        fi
    fi
    
    chunk_name="[$chunk_start-$chunk_end]"
    start_snap="${snapshot_array[$chunk_start]}"
    end_snap="${snapshot_array[$chunk_end]}"
    
    # Extract snapshot names for ZFS destroy command
    start_snap_name="${start_snap#*@}"
    end_snap_name="${end_snap#*@}"
    
    if [[ "$debug_mode" == true ]]; then
        echo "Chunk: $chunk_name"
        echo "  Start snap: $start_snap"
        echo "  End snap: $end_snap"
        echo "  Start snap name: $start_snap_name"
        echo "  End snap name: $end_snap_name"
        echo "  Most recent name: $most_recent_snap_name"
        
        if [[ "$chunk_to_latest_mode" == true ]]; then
            # Chunk-to-latest mode: from start of chunk to most recent snapshot
            destroy_flags="-nv"
            if [[ "$delete_mode" == true ]]; then
                destroy_flags="-v"
            fi
            echo "  Command would be: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$most_recent_snap_name\""
            echo "  Running: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$most_recent_snap_name\""
            destroy_output=$(zfs destroy $destroy_flags "$dataset_name@$start_snap_name%$most_recent_snap_name" 2>&1)
        else
            # Chunk mode (default): calculate whole reclaimable space of chunk
            # Note: snapshot_array is now in chronological order (oldest first)
            if [[ -n "$target_spec" ]]; then
                # Sub-chunk mode: special handling for last sub-chunk
                if [[ "$chunk_num" -eq "$divide_by" || ("$divide_by" -eq 0 && "$chunk_end" -eq $((total_snapshots - 1))) ]]; then
                    # Last sub-chunk
                    if [[ "$target_is_last_chunk" == true ]]; then
                        # Original chunk was last chunk: from start of sub-chunk to end of original chunk
                        original_end_snap="${snapshot_array[$((total_snapshots - 1))]}"
                        original_end_snap_name="${original_end_snap#*@}"
                        destroy_flags="-nv"
                        if [[ "$delete_mode" == true ]]; then
                            destroy_flags="-v"
                        fi
                        echo "  Command would be: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$original_end_snap_name\""
                        echo "  Running: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$original_end_snap_name\""
                        destroy_output=$(zfs destroy $destroy_flags "$dataset_name@$start_snap_name%$original_end_snap_name" 2>&1)
                    else
                        # Original chunk was not last: from start of sub-chunk to first snap of next original chunk
                        next_chunk_first_snap_name="${next_chunk_first_snap#*@}"
                        destroy_flags="-nv"
                        if [[ "$delete_mode" == true ]]; then
                            destroy_flags="-v"
                        fi
                        echo "  Command would be: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$next_chunk_first_snap_name\""
                        echo "  Running: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$next_chunk_first_snap_name\""
                        destroy_output=$(zfs destroy $destroy_flags "$dataset_name@$start_snap_name%$next_chunk_first_snap_name" 2>&1)
                    fi
                else
                    # Not last sub-chunk: from start of current sub-chunk to start of next sub-chunk
                    next_chunk_start=$((chunk_end + 1))
                    next_start_snap="${snapshot_array[$next_chunk_start]}"
                    next_start_snap_name="${next_start_snap#*@}"
                    destroy_flags="-nv"
                    if [[ "$delete_mode" == true ]]; then
                        destroy_flags="-v"
                    fi
                    echo "  Command would be: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$next_start_snap_name\""
                    echo "  Running: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$next_start_snap_name\""
                    destroy_output=$(zfs destroy $destroy_flags "$dataset_name@$start_snap_name%$next_start_snap_name" 2>&1)
                fi
            else
                # Regular chunk mode
                if [[ "$chunk_num" -eq "$divide_by" || ("$divide_by" -eq 0 && "$chunk_end" -eq $((total_snapshots - 1))) ]]; then
                    # Last chunk: from start of chunk to end of chunk
                    destroy_flags="-nv"
                    if [[ "$delete_mode" == true ]]; then
                        destroy_flags="-v"
                    fi
                    echo "  Command would be: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$end_snap_name\""
                    echo "  Running: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$end_snap_name\""
                    destroy_output=$(zfs destroy $destroy_flags "$dataset_name@$start_snap_name%$end_snap_name" 2>&1)
                else
                    # Not last chunk: from start of current chunk to start of next chunk
                    next_chunk_start=$((chunk_end + 1))
                    next_start_snap="${snapshot_array[$next_chunk_start]}"
                    next_start_snap_name="${next_start_snap#*@}"
                    destroy_flags="-nv"
                    if [[ "$delete_mode" == true ]]; then
                        destroy_flags="-v"
                    fi
                    echo "  Command would be: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$next_start_snap_name\""
                    echo "  Running: zfs destroy $destroy_flags \"$dataset_name@$start_snap_name%$next_start_snap_name\""
                    destroy_output=$(zfs destroy $destroy_flags "$dataset_name@$start_snap_name%$next_start_snap_name" 2>&1)
                fi
            fi
        fi
        exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            # Extract the reclaim size from the output - get the value after "would reclaim"
            reclaim_size=$(echo "$destroy_output" | grep "would reclaim" | awk '{print $NF}')
            if [[ -n "$reclaim_size" ]]; then
                echo "  Would reclaim: $reclaim_size"
            else
                echo "  Would reclaim: 0B"
            fi
        else
            echo "  Would reclaim: ERROR"
            echo "  Error: $destroy_output"
        fi
        echo ""
    fi
    
    if [[ -n "$chunks" ]]; then
        chunks+=$'\n'
    fi
    chunks+="$chunk_name"$'\t'"$start_snap"$'\t'"$end_snap"$'\t'"$most_recent_snap_name"
    
    # If we just processed the targeted sub-chunk, exit the loop
    if [[ -n "$sub_chunk_target" && "$chunk_num" == "$sub_chunk_target" ]]; then
        break
    fi
    
    chunk_start=$((chunk_end + 1))
    chunk_num=$((chunk_num + 1))
done

if [[ "$debug_mode" == true ]]; then
    echo "Final chunks data:"
    echo "$chunks"
    echo ""
fi

# Summary output in the requested format
if [[ -n "$target_spec" ]]; then
    echo "=== SUMMARY: Sub-chunk reclaim sizes (from chunk $target_chunk) ==="
else
    echo "=== SUMMARY: Chunk reclaim sizes ==="
fi

if [[ "$chunk_to_latest_mode" == true ]]; then
    mode_note="chunk-to-latest: each chunk to most recent snapshot"
else
    mode_note="chunk mode: reclaim space from first to last snapshot in chunk"
fi
echo "($mode_note)"
echo "Most recent snapshot: $most_recent_snap_name"
echo "ℹ️ Note: Sum of chunk reclaim sizes may not equal total reclaimable space due to shared blocks between snapshots."

# Header for summary table
printf "%-12s %-12s %-46s %-10s\n" "Chunk" "Range" "Start Snapshot" "Reclaim"
printf "%s\n" "--------------------------------------------------------------------------------------"

chunk_num=1
chunk_start=0

# Calculate total number of chunks for formatting
if [[ "$divide_by" -gt 0 ]]; then
    total_chunks="$divide_by"
else
    # Calculate how many chunks there will be
    if [[ "$chunk_size" -gt 0 ]]; then
        total_chunks=$(( (total_snapshots + chunk_size - 1) / chunk_size ))
    else
        total_chunks=1
    fi
fi

# Determine the width for chunk numbers and chunk ranges
chunk_num_width=${#total_chunks}
chunk_range_width=$(( ${#total_snapshots} + 1 ))
if (( chunk_range_width < 2 )); then
    chunk_range_width=2
fi

# This is the primary loop for snapshot chunk processing

while [[ "$chunk_start" -lt "$total_snapshots" && ("$divide_by" -eq 0 || "$chunk_num" -le "$divide_by") ]]; do
    # Update context tracking
    if [[ -n "$target_spec" ]]; then
        current_chunk_context="$target_chunk"
        current_sub_chunk_num="$chunk_num"
    else
        current_chunk_context="$chunk_num"
        current_sub_chunk_num=0  # Not in sub-chunk mode
    fi
    
    # Skip processing if we're only interested in a specific chunk and this isn't it
    if [[ -n "$delete_coordinates" && -z "$target_spec" && "$current_chunk_context" != "$target_chunk" ]]; then
        # Correctly calculate chunk_end before skipping
        if [[ "$divide_by" -gt 0 && "$chunk_num" -eq "$divide_by" ]]; then
            chunk_end=$((total_snapshots - 1))
        else
            chunk_end=$((chunk_start + chunk_size - 1))
            if [[ "$chunk_end" -ge "$total_snapshots" ]]; then
                chunk_end=$((total_snapshots - 1))
            fi
        fi
        chunk_start=$((chunk_end + 1))
        chunk_num=$((chunk_num + 1))
        continue
    fi
    
    # Skip processing if we're only interested in a specific sub-chunk and this isn't it
    if [[ -n "$sub_chunk_target" && "$current_sub_chunk_num" != "$sub_chunk_target" ]]; then
        # Calculate the chunk end to move past this sub-chunk
        if [[ "$divide_by" -gt 0 && "$chunk_num" -eq "$divide_by" ]]; then
            chunk_end=$((total_snapshots - 1))
        else
            chunk_end=$((chunk_start + chunk_size - 1))
            if [[ "$chunk_end" -ge "$total_snapshots" ]]; then
                chunk_end=$((total_snapshots - 1))
            fi
        fi
        chunk_start=$((chunk_end + 1))
        chunk_num=$((chunk_num + 1))
        continue
    fi
    # For the last chunk, include all remaining snapshots
    if [[ "$divide_by" -gt 0 && "$chunk_num" -eq "$divide_by" ]]; then
        chunk_end=$((total_snapshots - 1))
    else
        chunk_end=$((chunk_start + chunk_size - 1))
        if [[ "$chunk_end" -ge "$total_snapshots" ]]; then
            chunk_end=$((total_snapshots - 1))
        fi
    fi

    start_snap="${snapshot_array[$chunk_start]}" 
    end_snap="${snapshot_array[$chunk_end]}" # Last snapshot in the current chunk

    # Extract snapshot names for ZFS destroy command
    start_snap_name="${start_snap#*@}" 
    end_snap_name="${end_snap#*@}"

    # Create chunk range for display - show original indices when using chunk spec
    if [[ -n "$target_spec" ]]; then 
        # Calculate original indices from the target chunk
        original_start=$((target_start + chunk_start))
        original_end=$((target_start + chunk_end))
        chunk_range_start=$(printf "%0${chunk_range_width}d" "$original_start")
        chunk_range_end=$(printf "%0${chunk_range_width}d" "$original_end")
        chunk_range="[$chunk_range_start-$chunk_range_end]"
    else
        chunk_range_start=$(printf "%0${chunk_range_width}d" "$chunk_start")
        chunk_range_end=$(printf "%0${chunk_range_width}d" "$chunk_end")
        chunk_range="[$chunk_range_start-$chunk_range_end]"
    fi

    # Format chunk number with leading zeros
    chunk_num_fmt=$(printf "%0${chunk_num_width}d" "$chunk_num") 
    
    # Format snapshot name to exactly 45 characters (truncate if longer, pad if shorter)
    if [[ ${#start_snap_name} -gt 44 ]]; then
        # Truncate to 44 characters and add "..." to indicate truncation
        formatted_snap_name="${start_snap_name:0:41}..."
    else
        # Pad to 44 characters with spaces 
        formatted_snap_name=$(printf "%-44s" "$start_snap_name")
    fi
    
    # Run the actual ZFS destroy command to get the reclaim size for summary 
    destroy_command=""
    end_ref_snap=""

    if [[ "$chunk_to_latest_mode" == true ]]; then
        # Chunk-to-latest mode: from start of chunk to most recent snapshot
        destroy_flags="-nv"
        destroy_command="$dataset_name@$start_snap_name%$most_recent_snap_name"

        if [[ "$delete_mode" == true ]]; then
            destroy_flags="-v"
            # Get chunk info for confirmation
            if [[ -n "$target_spec" ]]; then
                chunk_type="sub-chunk"
                chunk_id="$target_chunk-$chunk_num_fmt"
            else
                chunk_type="chunk"
                chunk_id="$chunk_num_fmt"
            fi
            # Get reclaim size first for confirmation
            dry_run_output=$(zfs destroy -nv "$destroy_command" 2>&1)
            reclaim_size=$(echo "$dry_run_output" | grep "would reclaim" | awk '{print $NF}')
            if [[ -z "$reclaim_size" ]]; then
                reclaim_size="0B"
            fi
            # Build snapshot list for confirmation
            snapshot_list=""
            start_idx_in_original=-1
            for ((i=0; i<original_total_snapshots; i++)); do
                if [[ "${original_snapshot_array[$i]}" == "$start_snap" ]]; then
                    start_idx_in_original=$i
                    break
                fi
            done

            if [[ "$start_idx_in_original" -ne -1 ]]; then
                for ((i=start_idx_in_original; i<original_total_snapshots; i++)); do
                    if [[ -n "$snapshot_list" ]]; then
                        snapshot_list+=$'\n'
                    fi
                    snapshot_list+="${original_snapshot_array[$i]}"
                done
            fi
            # Confirm deletion
            if ! confirm_deletion "$chunk_type" "$chunk_id" "$start_snap" "$dataset_name@$most_recent_snap_name" "$reclaim_size" "$snapshot_list"; then
                echo "Deletion cancelled."
                exit 0
            fi
        fi
        
        if [[ "$debug_mode" == true ]]; then
            echo ""
            echo "Chunk: $chunk_range"
            echo "  Mode: chunk-to-latest"
            echo "  Start snap: $start_snap"
            echo "  End snap:   (most recent)"
            echo "  Command: zfs destroy $destroy_flags \"$destroy_command\""
        fi

        destroy_output=$(zfs destroy $destroy_flags "$destroy_command" 2>&1)
        exit_code=$?

        if [[ $exit_code -eq 0 && "$delete_mode" == true && (-n "$delete_coordinates" || -n "$sub_chunk_target") ]]; then
            echo "Deletion completed successfully."
            exit 0
        fi
    else
        # Chunk mode (default): destroy snapshots from the start to the end of the current chunk.
        destroy_flags="-nv"
        destroy_command="$dataset_name@$start_snap_name%$end_snap_name"
        end_ref_snap="$end_snap"

        if [[ "$delete_mode" == true ]]; then
            destroy_flags="-v"
            # Get chunk info for confirmation
            if [[ -n "$target_spec" ]]; then
                chunk_type="sub-chunk"
                chunk_id="$target_chunk-$chunk_num_fmt"
            else
                chunk_type="chunk"
                chunk_id="$chunk_num_fmt"
            fi

            # Get reclaim size first for confirmation
            dry_run_output=$(zfs destroy -nv "$destroy_command" 2>&1)
            reclaim_size=$(echo "$dry_run_output" | grep "would reclaim" | awk '{print $NF}')
            if [[ -z "$reclaim_size" ]]; then
                reclaim_size="0B"
            fi

            # Build snapshot list for confirmation (from start of chunk to end of chunk)
            snapshot_list=""
            for ((i=chunk_start; i<=chunk_end; i++)); do
                if [[ -n "$snapshot_list" ]]; then
                    snapshot_list+=$'\n'
                fi
                snapshot_list+="${snapshot_array[$i]}"
            done

            # Confirm deletion
            if ! confirm_deletion "$chunk_type" "$chunk_id" "$start_snap" "$end_ref_snap" "$reclaim_size" "$snapshot_list"; then
                echo "Deletion cancelled."
                exit 0
            fi
        fi

        if [[ "$debug_mode" == true ]]; then
            echo ""
            echo "Chunk: $chunk_range"
            if [[ -n "$target_spec" ]]; then
              echo "  Mode: sub-chunk"
            else
              echo "  Mode: chunk"
            fi
            echo "  Start snap: $start_snap"
            echo "  End snap:   $end_snap"
            echo "  Command: zfs destroy $destroy_flags \"$destroy_command\""
        fi

        destroy_output=$(zfs destroy $destroy_flags "$destroy_command" 2>&1)
        exit_code=$?

        if [[ $exit_code -eq 0 && "$delete_mode" == true && (-n "$delete_coordinates" || -n "$sub_chunk_target") ]]; then
            echo "Deletion completed successfully."
            exit 0
        fi
    fi
    exit_code=$? 
    
    # Extract the reclaim size from the output - get the value after "would reclaim"
    reclaim_size=$(echo "$destroy_output" | grep "would reclaim" | awk '{print $NF}')

    if [[ $exit_code -eq 0 ]]; then
        if [[ -z "$reclaim_size" ]]; then reclaim_size="0B"; fi

        if [[ -n "$target_spec" ]]; then
            printf "sub-chunk %-4s %-12s %-46s %-10s\n" "$target_chunk-$chunk_num_fmt" "$chunk_range" "$formatted_snap_name" "$reclaim_size"
        else
            printf "chunk %-7s %-12s %-46s %-10s\n" "$chunk_num_fmt" "$chunk_range" "$formatted_snap_name" "$reclaim_size"
        fi
    else
        if [[ -n "$target_spec" ]]; then
            printf "sub-chunk %-4s %-12s %-46s %-10s\n" "$target_chunk-$chunk_num_fmt" "$chunk_range" "$formatted_snap_name" "ERROR"
        else
            printf "chunk %-7s %-12s %-46s %-10s\n" "$chunk_num_fmt" "$chunk_range" "$formatted_snap_name" "ERROR"
        fi
        if [[ "$debug_mode" == true ]]; then
            # Indent error message for readabilit
            echo "  Error details: $destroy_output"
        fi
    fi
    
    # If we just processed the targeted sub-chunk, exit the loop
    if [[ -n "$sub_chunk_target" && "$chunk_num" == "$sub_chunk_target" ]]; then
        break
    fi
    
    chunk_start=$((chunk_end + 1))
    chunk_num=$((chunk_num + 1))
done