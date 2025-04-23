Summary of the Script’s Functionality


This Bash script, designed for macOS and integrated with Jamf, monitors system uptime and prompts users to restart their Mac when it exceeds a specified threshold (default: 0 days). It includes user interaction, deferral options, a countdown timer, and debug capabilities. Here’s what it does step-by-step:


1. Uptime Check:
    * Calculates the system uptime in days using sysctl kern.boottime.
    * Compares it against MAX_DAYS (default: 0 days).


1. User Prompting:
    * If uptime exceeds MAX_DAYS, it uses jamfHelper to display a HUD-style prompt with a custom logo (default: Viewpoint logo, fallback to system icon).
    * Initial Behavior (Deferrals < 3):
        * Shows: "Your Mac has been running for X days... You can defer Y more time(s) before a forced restart."
        * Options: "Restart Now" or "Defer".
        * Timeout: 5 minutes (300 seconds), after which it exits silently if not forced.
    * After 3 Deferrals:
        * Shows: "You have deferred the restart 3 times. You must restart now."
        * Displays a countdown from 5 minutes (e.g., "5:00", "4:50", updated every 10 seconds).
        * Option: "Restart Now" only.
        * Times out after 5 minutes, triggering a forced restart.


1. Deferral Logic:
    * Tracks deferrals in /tmp/uptime_defer_count.txt, with a limit of 3 (DEFER_LIMIT).
    * Each "Defer" choice increments the count and shows a confirmation: "You have Y deferral(s) remaining."
    * Resets the count to 0 after a restart (simulated or real).
2. Restart Handling:
    * Normal Mode: Executes /sbin/shutdown -r now to restart the Mac when "Restart Now" is clicked or the countdown times out after 3 deferrals (requires root privileges).
    * Debug Mode: Simulates the restart (logs "Restart simulated" and resets defer count) without rebooting, allowing repeated testing.
3. Logging and Debugging:
    * Logs all actions (e.g., deferrals, restarts, errors) to /tmp/uptime_checker.log.
    * In debug mode (enabled with -d or --debug flag, or by setting DEBUG=true), adds detailed DEBUG:messages to the log and console, and bypasses actual restarts.
4. Error Handling:
    * Checks for macOS, jamfHelper availability, and file write permissions.
    * Displays error dialogs via jamfHelper if uptime retrieval fails or restart cannot proceed.


Key Features
* Purpose: Encourages regular restarts to maintain system performance.
* User Experience: Allows up to 3 deferrals before enforcing a restart with a 5-minute countdown.
* Debug Mode: Facilitates testing by simulating restarts without rebooting.
* Jamf Integration: Uses jamfHelper for polished UI prompts, assumes deployment via Jamf for permissions.


Default Behavior
* With DEBUG=false and no arguments: Prompts for restart if uptime > 0 days, enforces after 3 deferrals with a countdown.
* With DEBUG=true or -d: Same flow, but restarts are simulated, resetting the defer count for further testing.
