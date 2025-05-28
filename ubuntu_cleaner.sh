#!/bin/bash

# Ubuntu Cleaner Script
# Provides a GUI to select and perform various system cleaning tasks.

# --- Function to check and install dependencies ---
install_dependencies() {
    local missing_deps=()
    local deps_to_check=("zenity" "deborphan" "bleachbit") # Core dependencies

    echo "Checking for required dependencies..."

    for dep in "${deps_to_check[@]}"; do
        if ! command -v "$dep" >/dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "The following dependencies are missing: ${missing_deps[*]}"
        if zenity --question --text="The following dependencies are missing:<b> ${missing_deps[*]}</b>\n\nDo you want to try and install them now using APT?\n(Requires sudo privileges)" --width=450 --height=150; then
            echo "Attempting to install missing dependencies..."
            # shellcheck disable=SC2086 # We want word splitting for the array elements
            if sudo apt update && sudo apt install -y ${missing_deps[*]}; then
                echo "Dependencies installed successfully."
                # Re-check to be absolutely sure
                for dep_check_after_install in "${missing_deps[@]}"; do
                    if ! command -v "$dep_check_after_install" >/dev/null; then
                        zenity --error --text="Failed to install or find '$dep_check_after_install' even after attempting installation. Please install it manually and try again." --width=400
                        exit 1
                    fi
                done
            else
                zenity --error --text="Failed to install dependencies. Please install them manually and try again:\nsudo apt install ${missing_deps[*]}" --width=400
                exit 1
            fi
        else
            zenity --info --text="Dependency installation declined. The script cannot continue without: ${missing_deps[*]}" --width=400
            exit 1
        fi
    else
        echo "All required dependencies are present."
    fi
}

# --- Cleaning Task Functions ---

do_apt_clean() {
    echo "# Task: Standard APT Cleanup"
    echo "## Cleaning APT package cache..."
    sudo apt clean || echo "APT clean failed, continuing..."
    echo "## Cleaning obsolete downloaded package files..."
    sudo apt autoclean || echo "APT autoclean failed, continuing..."
    echo "## Removing automatically installed packages no longer needed..."
    sudo apt autoremove --purge -y || echo "APT autoremove failed, continuing..."
    
    if command -v deborphan >/dev/null; then
        echo "## Removing orphaned packages identified by deborphan..."
        # xargs -r ensures command only runs if deborphan outputs something
        sudo deborphan | xargs -r sudo apt-get -y remove --purge || echo "Deborphan removal failed or no packages found, continuing..."
    else
        echo "## deborphan not found, skipping deborphan step."
    fi
    
    echo "## Purging configuration files of already removed packages ('rc' state)..."
    # shellcheck disable=SC2046 # We want word splitting from awk output
    PKG_TO_PURGE=$(dpkg -l | grep '^rc' | awk '{print $2}')
    if [ -n "$PKG_TO_PURGE" ]; then
        # shellcheck disable=SC2086 # We want word splitting for $PKG_TO_PURGE list
        sudo apt purge -y $PKG_TO_PURGE || echo "Purging 'rc' packages failed, continuing..."
    else
        echo "## No 'rc' state packages found to purge."
    fi
}

do_old_kernels() {
    echo "# Task: Removing Old Kernels"
    CURRENT_KERNEL_VERSION=$(uname -r)
    echo "## Current running kernel: $CURRENT_KERNEL_VERSION (will be kept)"

    # List installed kernel image packages, excluding the currently running one, sorted by version
    # This regex tries to match common kernel package naming conventions
    INSTALLED_OTHER_KERNELS=$(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*[0-9.-]*(generic|lowlatency|aws|azure|gcp|oracle|signed-generic|signed-lowlatency)' 2>/dev/null | grep -vE "^linux-image-$(uname -r | sed 's/-generic\|-lowlatency//')\$" | grep -v "$CURRENT_KERNEL_VERSION" | sort -V)

    KERNELS_TO_REMOVE=""
    # Keep the current one (implicitly) + this many more of the most recent *other* installed kernels
    COUNT_OF_OTHER_KERNELS_TO_KEEP=1 
    
    if [ -z "$INSTALLED_OTHER_KERNELS" ]; then
        echo "## No other kernel images found besides the current one."
        return
    fi

    TOTAL_OTHER_KERNELS=$(echo "$INSTALLED_OTHER_KERNELS" | wc -l)
    NUM_TO_REMOVE=$(( TOTAL_OTHER_KERNELS - COUNT_OF_OTHER_KERNELS_TO_KEEP ))

    if [ "$NUM_TO_REMOVE" -gt 0 ]; then
        # Get the oldest N kernels from the "other kernels" list
        KERNELS_TO_REMOVE=$(echo "$INSTALLED_OTHER_KERNELS" | head -n "$NUM_TO_REMOVE")
    fi

    if [ -n "$KERNELS_TO_REMOVE" ]; then
        echo "## The following old kernel packages are candidates for removal:"
        # Format for display in Zenity
        KERNELS_TO_REMOVE_DISPLAY=$(echo "$KERNELS_TO_REMOVE" | awk '{printf "- %s\n", $0}')
        
        if zenity --question --text="Do you want to remove these old kernel packages?\n\n$KERNELS_TO_REMOVE_DISPLAY\n\n(Current kernel: <b>$CURRENT_KERNEL_VERSION</b> and <b>$COUNT_OF_OTHER_KERNELS_TO_KEEP</b> most recent other kernel(s) will be kept)" --width=500 --height=300; then
            echo "## Removing selected old kernels..."
            # shellcheck disable=SC2086 # We want word splitting for $KERNELS_TO_REMOVE
            sudo apt-get remove --purge -y $KERNELS_TO_REMOVE || echo "Old kernel removal failed, continuing..."
            echo "## Updating GRUB configuration..."
            sudo update-grub || echo "update-grub failed, continuing..."
        else
            echo "## Old kernel removal skipped by user."
        fi
    else
        echo "## No old kernels found to remove (or only essential ones remain based on keep count)."
    fi
}

do_clean_logs() {
    echo "# Task: Cleaning System Logs"
    echo "## Vacuuming journald logs (keeping last 7 days or max 500MB)..."
    sudo journalctl --vacuum-time=7d || sudo journalctl --vacuum-size=500M || echo "Journal vacuum failed, continuing..."
    
    echo "## Deleting archived log files (.gz, .old, numeric rotations)..."
    # Delete gzipped logs
    sudo find /var/log -type f -name "*.gz" -delete || echo "Failed to delete .gz logs, continuing..."
    # Delete rotated logs like daemon.log.1, messages.1 (but not .1.gz which is covered above)
    sudo find /var/log -type f -regex ".*\.[0-9]$" -delete || echo "Failed to delete numeric rotated logs, continuing..."
    # Delete .old logs
    sudo find /var/log -type f -name "*.old" -delete || echo "Failed to delete .old logs, continuing..."
    
    echo "## Note: Active log files (e.g., /var/log/syslog) are NOT truncated by this script for safety."
}

do_user_cache() {
    echo "# Task: Clearing User Cache"
    if [ -d "$HOME/.cache" ]; then
        local cache_size
        cache_size=$(du -sh "$HOME/.cache" | cut -f1)
        if zenity --question --text="Delete contents of <b>$HOME/.cache/*</b> ?\nApproximate size: <b>$cache_size</b>\n\nThis is generally safe, but some applications might need to rebuild their cache, which could take a moment on next launch." --width=450 --height=180; then
            echo "## Clearing user cache directory: $HOME/.cache/"
            # Use find to delete contents, safer than rm -rf ~/.cache/* for hidden files/dirs directly under .cache
            find "$HOME/.cache" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || echo "Failed to delete some user cache files, continuing..."
            # Recreate some common directories that applications expect
            mkdir -p "$HOME/.cache/thumbnails" "$HOME/.cache/fontconfig"
            echo "## User cache cleared."
        else
            echo "## User cache deletion skipped."
        fi
    else
        echo "## User cache directory ($HOME/.cache) not found."
    fi
}

do_bleachbit_user() {
    echo "# Task: Running BleachBit (User)"
    # Dependency 'bleachbit' checked by install_dependencies
    echo "## Configuring BleachBit user preset..."
    mkdir -p "$HOME/.config/bleachbit"
cat <<EOF > "$HOME/.config/bleachbit/cleaner.json"
{
  "system.cache": true,
  "system.clipboard": true,
  "system.custom": true,
  "system.recent_documents": true,
  "system.tmp": true,
  "system.trash": true,
  "apt.autoclean": true,
  "apt.autoremove": true,
  "apt.clean": true,
  "bash.history": false,
  "thumbnails.cache": true,
  "firefox.cache": true,
  "firefox.cookies": false,
  "firefox.download_history": true,
  "firefox.forms": false,
  "firefox.passwords": false,
  "firefox.session_restore": false,
  "firefox.site_preferences": false,
  "firefox.url_history": false,
  "google_chrome.cache": true,
  "google_chrome.cookies": false,
  "google_chrome.form_history": false,
  "google_chrome.history": false,
  "google_chrome.passwords": false,
  "google_chrome.search_engines": false
}
EOF
    echo "## Running BleachBit for current user with preset..."
    bleachbit --preset --clean || echo "User BleachBit run failed or was cancelled, continuing..."
}

do_bleachbit_root() {
    echo "# Task: Running BleachBit (Root)"
    # Dependency 'bleachbit' checked by install_dependencies
    if zenity --question --text="Run BleachBit as <b>root</b> (system-wide cleaning)?\n\nThis will use root's BleachBit presets or defaults if none are configured for root.\nEnsure root's presets are configured safely if you use custom ones there." --width=450 --height=180; then
        echo "## Running BleachBit as root with preset..."
        sudo bleachbit --preset --clean || echo "Root BleachBit run failed or was cancelled, continuing..."
    else
        echo "## Root BleachBit run skipped."
    fi
}

do_snap_clean() {
    echo "# Task: Cleaning Snap Packages"
    if command -v snap >/dev/null; then
        echo "## Checking for disabled Snap revisions..."
        
        mapfile -t disabled_snaps < <(snap list --all | awk '/disabled/{print $1, $3}')

        if [ ${#disabled_snaps[@]} -eq 0 ]; then
            echo "## No disabled snap revisions found."
        else
            local snap_rev_display=""
            for item in "${disabled_snaps[@]}"; do
                 snap_rev_display+="- $item\n"
            done
            
            if zenity --question --text="Found <b>${#disabled_snaps[@]}</b> disabled snap revisions:\n\n$snap_rev_display\nDo you want to remove them interactively?" --width=450 --height=300; then
                for item in "${disabled_snaps[@]}"; do
                    # Read snapname and revision from the item
                    read -r snapname revision <<< "$item"
                    if zenity --question --text="Remove disabled Snap: <b>$snapname</b> (revision <b>$revision</b>)?"; then
                        echo "### Removing snap $snapname revision $revision..."
                        sudo snap remove "$snapname" --revision="$revision" || echo "### Failed to remove snap $snapname rev $revision"
                    else
                        echo "### Skipped removing $snapname revision $revision."
                    fi
                done
            else
                echo "## Skipped removing disabled snap revisions."
            fi
        fi
        echo "## For further Snap cleanup, consider manually running 'sudo snap remove <package_name>' for unwanted applications."
        echo "## List installed snaps with: snap list"
    else
        echo "## Snapd (snap command) not found, skipping Snap clean."
    fi
}

do_flatpak_clean() {
    echo "# Task: Cleaning Flatpak"
    if command -v flatpak >/dev/null; then
        echo "## Removing unused Flatpak runtimes and applications..."
        flatpak uninstall --unused -y || echo "Flatpak uninstall unused failed (perhaps nothing to remove), continuing..."
        echo "## For further Flatpak cleanup, list installed flatpaks with: flatpak list"
        echo "## To remove a specific flatpak: flatpak uninstall <application-id>"
    else
        echo "## Flatpak command not found, skipping Flatpak clean."
    fi
}

do_docker_prune() {
    echo "# Task: Pruning Docker System"
    if command -v docker >/dev/null; then
        if ! docker info >/dev/null 2>&1; then
             echo "## Docker daemon doesn't seem to be running or accessible. Skipping Docker prune."
             zenity --warning --text="Could not connect to Docker daemon.\nPlease ensure Docker is running if you want to prune it." --width=400
             return
        fi

        echo "## Pruning Docker system (unused containers, networks, dangling images)..."
        if zenity --question --text="Run standard Docker prune: '<b>docker system prune -f</b>'?\n\nThis removes:\n- All stopped containers\n- All unused networks\n- All dangling images\n- All dangling build cache\n\nIt does <u>NOT</u> remove unused volumes by default." --width=500 --height=220; then
            sudo docker system prune -f || echo "Standard Docker system prune failed, continuing..."
        fi
        
        if zenity --question --text="<span color='red'><b>DANGER ZONE:</b></span> Run aggressive Docker prune: '<b>docker system prune -a --volumes -f</b>'?\n\nThis removes everything the standard prune does, PLUS:\n- <u>ALL unused images</u> (not just dangling ones)\n- <u>ALL unused volumes</u> (Caution: data in unnamed volumes will be lost!)\n\n<b>USE WITH EXTREME CAUTION!</b>" --width=500 --height=250; then
            sudo docker system prune -a --volumes -f || echo "Aggressive Docker system prune failed, continuing..."
        fi
    else
        echo "## Docker command not found, skipping Docker prune."
    fi
}

do_large_files_scan() {
    echo "# Task: Scanning for Large Files"
    local log_file="$HOME/large-files-scan-$(date +%Y%m%d-%H%M%S).log"
    echo "## Searching for files larger than 500MB system-wide (on the current '/' mount)..."
    echo "## This may take a significant amount of time. Results will be saved to: $log_file"
    
    # Using -print0 and xargs -0 for safety with filenames.
    # -mount ensures find stays on the same filesystem as '/'.
    # 2>/dev/null for find and du to suppress permission denied errors.
    # shellcheck disable=SC2024
    if sudo find / -mount -type f -size +500M -print0 2>/dev/null | xargs -0 -r -- sudo du -h 2>/dev/null | sort -rh > "$log_file"; then
        if [ -s "$log_file" ]; then # Check if log file is not empty
            echo "## Large file scan complete. Results saved to $log_file"
            zenity --info --text="Large file scan complete.\nResults saved to: <b>$log_file</b>\n\nReview this file and manually delete any unwanted large files." --width=450 --height=150
        else
            echo "## Large file scan complete. No files >500MB found or scan failed to write to log."
            zenity --info --text="Large file scan complete.\nNo files >500MB found on the '/' mount or the log is empty." --width=400
            rm -f "$log_file" # Remove empty log file
        fi
    else
        echo "## Large file scan command failed."
        zenity --error --text="Large file scan failed to execute properly. Check terminal output for details." --width=400
        # rm -f "$log_file" # Clean up potentially empty/partial log
    fi
}

# --- Main Script Execution ---

# 1. Check and Install Dependencies
install_dependencies

# 2. Initial Warning
if ! zenity --warning \
    --title="Ubuntu Cleaner - IMPORTANT CAUTION!" \
    --text="This script can perform significant cleaning actions on your system.\n\n- <b>Review each option carefully</b> in the next step before selecting.\n- Some actions, if misused, could lead to data loss or system issues.\n- It is <b>STRONGLY recommended to have backups</b> of important data before proceeding.\n\nAre you sure you want to continue?" \
    --width=550 --height=250 --ok-label="Proceed with Caution" --cancel-label="Exit"; then
    exit 0
fi

# 3. Task Selection GUI
CHOICES=$(zenity --list \
    --title="Ubuntu Cleaner Options" \
    --text="Select tasks to perform (use <b>Spacebar</b> to toggle, <b>Enter</b> to OK):" \
    --checklist \
    --column="Select" --column="Task ID" --column="Description" --width=850 --height=600 \
    TRUE  "apt_clean" "1. <b>Standard APT Cleanup</b> (cache, autoremove, deborphan, 'rc' configs)" \
    TRUE  "old_kernels" "2. <b>Remove Old Kernels</b> (keeps current & 1 previous, interactive)" \
    TRUE  "clean_logs" "3. <b>Clean System Logs</b> (journal vacuum, delete old *.gz, *.1, *.old files)" \
    FALSE "user_cache" "4. Clear User Cache (<b>~/.cache/*</b> - interactive, generally safe)" \
    FALSE "bleachbit_user" "5. Run BleachBit (<b>User</b> - uses preset, requires BleachBit)" \
    FALSE "bleachbit_root" "6. Run BleachBit (<b>Root</b> - system-wide, interactive, requires BleachBit)" \
    TRUE "snap_clean" "7. Clean Snap Pkgs (remove <b>disabled revisions</b> - interactive)" \
    TRUE "flatpak_clean" "8. Clean Flatpak (remove <b>unused runtimes/apps</b>)" \
    FALSE "docker_prune" "9. Prune Docker System (<b>CAUTION</b> - interactive for standard and aggressive prune)" \
    FALSE "large_files" "10. Scan for Large Files (>500MB, logs to ~/large-files-scan-DATE.log)" \
)

# Exit if no choice is made or dialog is cancelled
if [ -z "$CHOICES" ]; then
    zenity --info --text="No tasks selected. Exiting script."
    exit 0
fi

IFS='|' read -ra SELECTED_TASKS <<< "$CHOICES"
TOTAL_TASKS=${#SELECTED_TASKS[@]}
COMPLETED_TASKS=0

# 4. Zenity Progress Pipeline for selected tasks
(
# Add a small delay for Zenity to pop up before first echo
sleep 0.5 
echo "0"
echo "# Initializing cleanup process..."

for task_id in "${SELECTED_TASKS[@]}"; do
    # Calculate percentage before starting the task (for the text update)
    current_progress_text_percentage=$(( (COMPLETED_TASKS * 100) / TOTAL_TASKS ))
    echo "$current_progress_text_percentage" # Update progress bar value

    # Execute the selected task
    case "$task_id" in
        "apt_clean")         do_apt_clean ;;
        "old_kernels")       do_old_kernels ;;
        "clean_logs")        do_clean_logs ;;
        "user_cache")        do_user_cache ;;
        "bleachbit_user")    do_bleachbit_user ;;
        "bleachbit_root")    do_bleachbit_root ;;
        "snap_clean")        do_snap_clean ;;
        "flatpak_clean")     do_flatpak_clean ;;
        "docker_prune")      do_docker_prune ;;
        "large_files")       do_large_files_scan ;;
        *)                   echo "# Unknown task ID: $task_id (Skipping)" ;;
    esac

    COMPLETED_TASKS=$((COMPLETED_TASKS + 1))
    # Calculate percentage after task completion for the next update or final 100%
    final_progress_percentage_for_task=$(( (COMPLETED_TASKS * 100) / TOTAL_TASKS ))
    echo "$final_progress_percentage_for_task" # Update progress bar value
done

# Ensure 100% is shown at the very end and final message
echo "100"
echo "# All selected tasks have been processed."
sleep 1 # Give time for the 100% and final message to show before auto-close

) | zenity --progress \
    --title="Ubuntu Cleaner" \
    --text="Starting system cleanup..." \
    --percentage=0 \
    --auto-close \
    --pulsate \
    --width=550 \
    --height=180

# 5. Final Completion Message
SUMMARY_MSG="✅ Selected cleanup tasks complete."
# Check if large_files task was run to remind about the log file
if [[ " ${SELECTED_TASKS[*]} " =~ " large_files " ]]; then
    # Find the most recent large-files-scan log
    # This assumes the log was created if the task ran, even if empty.
    # A more robust way would be to get the log_file variable from the function if possible,
    # or just use a generic message.
    LATEST_LARGE_FILE_LOG=$(ls -t "$HOME"/large-files-scan-*.log 2>/dev/null | head -n 1)
    if [ -n "$LATEST_LARGE_FILE_LOG" ] && [ -s "$LATEST_LARGE_FILE_LOG" ]; then
        SUMMARY_MSG+="\n\nReview <b>$LATEST_LARGE_FILE_LOG</b> for any large files you might want to manually delete."
    elif [ -n "$LATEST_LARGE_FILE_LOG" ]; then # Log exists but is empty
        SUMMARY_MSG+="\n\nLarge file scan ran, but no files >500MB were found (or log is empty)."
    fi
fi
zenity --info --text="$SUMMARY_MSG" --width=450 --height=150

echo "Script finished."
