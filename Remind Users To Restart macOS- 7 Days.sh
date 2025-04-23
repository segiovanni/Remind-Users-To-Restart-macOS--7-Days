#!/bin/bash

# Script to check uptime and prompt for restart if > threshold days
# Enhanced with jamfHelper, logging, custom logo, defer counter, forced restart, and 3-minute save grace period
# Debug mode bypasses actual restarts for testing

# Debug flag (default: off)
DEBUG=false

# Check for debug flag
if [[ "$1" == "-d" || "$1" == "--debug" ]]; then
    DEBUG=true
fi

# Configuration variables
readonly MAX_DAYS=7  # Uptime threshold in days
readonly LOG_FILE="/tmp/uptime_checker.log"  # Accessible directory
readonly JAMF_HELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
readonly LOGO_PATH="/Library/Application Support/JAMF/JamfCustomApps/logo.png"
readonly FALLBACK_LOGO="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns"
readonly TIMEOUT_SECONDS=180  # 3 minutes (changed from 300)
readonly DEFER_LIMIT=3  # Maximum times user can defer restart
readonly DEFER_FILE="/tmp/uptime_defer_count.txt"  # Accessible directory
readonly SAVE_GRACE_SECONDS=180  # 3-minute grace period to save data

# Function to log messages with timestamp
log_message() {
    local message="$1"
    if ! echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE" 2>/dev/null; then
        echo "WARNING: Failed to write to $LOG_FILE, logging to console only" >&2
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >&2
    else
        echo "$message"
    fi
    $DEBUG && echo "DEBUG: $message" >&2
}

# Function to display error dialog
show_error_dialog() {
    local message="$1"
    $DEBUG && echo "DEBUG: Showing error dialog: $message" >&2
    "$JAMF_HELPER" \
        -windowType utility \
        -title "Error" \
        -description "$message" \
        -button1 "OK" \
        -icon "${effective_logo}" \
        -timeout 60 >/dev/null 2>&1
}

# Function to get defer count
get_defer_count() {
    if [[ -f "$DEFER_FILE" ]]; then
        cat "$DEFER_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
    $DEBUG && echo "DEBUG: Defer count retrieved: $(cat "$DEFER_FILE" 2>/dev/null || echo "0")" >&2
}

# Function to increment defer count
increment_defer_count() {
    local count=$(get_defer_count)
    (( count++ ))
    echo "$count" > "$DEFER_FILE" 2>/dev/null || log_message "ERROR: Failed to update defer count."
    $DEBUG && echo "DEBUG: Defer count incremented to $count" >&2
}

# Function to simulate or perform restart
perform_restart() {
    if $DEBUG; then
        log_message "DEBUG: Restart simulated (actual restart bypassed in debug mode)."
        rm -f "$DEFER_FILE"  # Still reset defer count for testing flow
        $DEBUG && echo "DEBUG: Defer count reset (simulated restart)" >&2
    else
        if /sbin/shutdown -r now 2>/dev/null; then
            log_message "Restart initiated successfully."
            rm -f "$DEFER_FILE"  # Reset defer count on successful restart
            $DEBUG && echo "DEBUG: Restart successful, defer count reset" >&2
        else
            log_message "ERROR: Restart failed or requires higher privileges."
            show_error_dialog "Unable to restart. Please try again or contact IT."
        fi
    fi
}

# Function to display save grace period prompt
show_save_prompt() {
    $DEBUG && echo "DEBUG: Displaying 3-minute save prompt" >&2
    "$JAMF_HELPER" \
        -windowType hud \
        -title "Restart Imminent" \
        -heading "Save Your Work" \
        -description "Your Mac will restart in 3 minutes. Please save all open documents now. Click 'Restart Now' to proceed immediately or wait for the automatic restart." \
        -button1 "Restart Now" \
        -defaultButton 1 \
        -icon "$effective_logo" \
        -timeout "$SAVE_GRACE_SECONDS" \
        >/dev/null 2>&1
    $DEBUG && echo "DEBUG: Save prompt completed or timed out" >&2
}

# Function to display prompt with countdown (for forced restart)
show_countdown_prompt() {
    local total_time=$TIMEOUT_SECONDS
    local interval=10  # Update every 10 seconds
    local elapsed=0
    local response=""

    $DEBUG && echo "DEBUG: Starting countdown prompt for $total_time seconds" >&2

    while [[ $elapsed -lt $total_time ]]; do
        local remaining=$((total_time - elapsed))
        local minutes=$((remaining / 60))
        local seconds=$((remaining % 60))
        local time_display=$(printf "%d:%02d" $minutes $seconds)

        description="Your Mac has been running for $uptime_days days (over $MAX_DAYS days). You have deferred the restart $DEFER_LIMIT times. You must restart now. Please save all work before proceeding. This prompt will time out in $time_display minutes."

        response=$("$JAMF_HELPER" \
            -windowType hud \
            -title "Restart Reminder" \
            -heading "Your Mac Needs Attention" \
            -description "$description" \
            -button1 "Restart Now" \
            -defaultButton 1 \
            -icon "$effective_logo" \
            -timeout $interval \
            2>/dev/null)

        # Check response
        if [[ "$response" == "0" ]]; then
            $DEBUG && echo "DEBUG: User chose Restart Now during countdown" >&2
            return 0  # User clicked "Restart Now"
        fi

        # If jamfHelper exits due to timeout, continue countdown
        elapsed=$((elapsed + interval))
        $DEBUG && echo "DEBUG: Countdown update - $remaining seconds remaining" >&2
    done

    # If loop completes (full timeout), return 1 to indicate timeout
    $DEBUG && echo "DEBUG: Countdown completed, timed out after $total_time seconds" >&2
    return 1
}

# Ensure log file is writable
$DEBUG && echo "DEBUG: Checking log file permissions" >&2
if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "ERROR: Cannot write to $LOG_FILE. Ensure directory is writable or run with sufficient privileges." >&2
    exit 1
fi

# Ensure defer file directory is writable
$DEBUG && echo "DEBUG: Checking defer file permissions" >&2
if ! touch "$DEFER_FILE" 2>/dev/null; then
    echo "ERROR: Cannot write to $DEFER_FILE. Ensure directory is writable or run with sufficient privileges." >&2
    exit 1
fi

# Check if running on macOS
$DEBUG && echo "DEBUG: Verifying OS" >&2
if [[ "$(uname -s)" != "Darwin" ]]; then
    log_message "ERROR: This script is intended for macOS only."
    exit 1
fi

# Verify jamfHelper exists
$DEBUG && echo "DEBUG: Checking jamfHelper" >&2
if [[ ! -x "$JAMF_HELPER" ]]; then
    log_message "ERROR: jamfHelper not found or not executable at $JAMF_HELPER."
    exit 1
fi

# Set logo path with fallback
effective_logo="$LOGO_PATH"
$DEBUG && echo "DEBUG: Setting logo to $effective_logo" >&2
if [[ ! -f "$LOGO_PATH" ]]; then
    log_message "WARNING: Logo file not found at $LOGO_PATH. Using default icon."
    effective_logo="$FALLBACK_LOGO"
    $DEBUG && echo "DEBUG: Falling back to $effective_logo" >&2
fi

# Get uptime in seconds and calculate days
$DEBUG && echo "DEBUG: Calculating uptime" >&2
uptime_seconds=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')
if [[ -z "$uptime_seconds" || ! "$uptime_seconds" =~ ^[0-9]+$ ]]; then
    log_message "ERROR: Failed to retrieve uptime from sysctl."
    show_error_dialog "Unable to check system uptime. Please contact IT."
    exit 1
fi

current_time=$(date +%s)
(( uptime_days = (current_time - uptime_seconds) / 86400 ))
$DEBUG && echo "DEBUG: Uptime calculated as $uptime_days days" >&2

# Check if uptime exceeds threshold
if [[ "$uptime_days" -gt "$MAX_DAYS" ]]; then
    log_message "System uptime is $uptime_days days—exceeds $MAX_DAYS-day threshold."

    # Get current defer count
    defer_count=$(get_defer_count)
    remaining_defers=$(( DEFER_LIMIT - defer_count ))
    $DEBUG && echo "DEBUG: Defer count: $defer_count, Remaining defers: $remaining_defers" >&2

    # Prepare message and buttons based on defer count
    if [[ "$defer_count" -ge "$DEFER_LIMIT" ]]; then
        force_restart=true
        $DEBUG && echo "DEBUG: Forcing restart with countdown (defer limit reached)" >&2

        # Show countdown prompt
        show_countdown_prompt
        response=$?

        if [[ "$response" -eq 0 ]]; then
            log_message "User chose to restart now."
            $DEBUG && echo "DEBUG: Showing 3-minute save prompt before restart" >&2
            show_save_prompt
            log_message "Initiating restart after save prompt."
            $DEBUG && echo "DEBUG: Initiating restart" >&2
            perform_restart
        else
            log_message "Prompt timed out after $((TIMEOUT_SECONDS/60)) minutes."
            $DEBUG && echo "DEBUG: Showing 3-minute save prompt before forced restart" >&2
            show_save_prompt
            log_message "Forcing restart after timeout and save prompt (defer limit reached)."
            $DEBUG && echo "DEBUG: Forcing restart after timeout" >&2
            perform_restart
        fi
    else
        description="Your Mac has been running for $uptime_days days (over $MAX_DAYS days). A restart is recommended to maintain performance. You can defer $remaining_defers more time(s) before a forced restart. Please save all work before restarting."
        buttons=(-button1 "Restart Now" -button2 "Defer" -defaultButton 2 -cancelButton 2)
        force_restart=false
        $DEBUG && echo "DEBUG: Offering restart choice" >&2

        # Prompt user with jamfHelper (no countdown)
        $DEBUG && echo "DEBUG: Displaying jamfHelper prompt without countdown" >&2
        response=$("$JAMF_HELPER" \
            -windowType hud \
            -title "Restart Reminder" \
            -heading "Your Mac Needs Attention" \
            -description "$description" \
            "${buttons[@]}" \
            -icon "$effective_logo" \
            -timeout "$TIMEOUT_SECONDS" \
            2>/dev/null)

        # Handle user response
        case "$response" in
            0)  # Restart Now
                log_message "User chose to restart now."
                $DEBUG && echo "DEBUG: Showing 3-minute save prompt before restart" >&2
                show_save_prompt
                log_message "Initiating restart after save prompt."
                $DEBUG && echo "DEBUG: Initiating restart" >&2
                perform_restart
                ;;
            2)  # Defer
                log_message "User chose to defer restart (defer $((defer_count + 1)) of $DEFER_LIMIT)."
                increment_defer_count
                "$JAMF_HELPER" \
                    -windowType hud \
                    -title "Restart Deferred" \
                    -heading "Reminder" \
                    -description "You have $((remaining_defers - 1)) deferral(s) remaining. After $DEFER_LIMIT deferrals, you will be required to restart." \
                    -button1 "OK" \
                    -icon "$effective_logo" \
                    -timeout 60 >/dev/null 2>&1
                ;;
            *)  # Timeout (no forced restart yet)
                log_message "Prompt timed out or was cancelled after $((TIMEOUT_SECONDS/60)) minutes."
                ;;
        esac
    fi
else
    log_message "System uptime is $uptime_days days—no restart needed (threshold: $MAX_DAYS days)."
fi

$DEBUG && echo "DEBUG: Script completed" >&2
exit 0
