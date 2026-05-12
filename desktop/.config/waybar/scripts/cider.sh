#!/bin/bash
set -euo pipefail

# Define the list of preferred media players (MPRIS IDs)
PREFERRED_PLAYERS="cider spotify"
ACTIVE_PLAYER_FILE="${XDG_RUNTIME_DIR:-/tmp}/waybar_active_player"

# Define the maximum length for the output text before truncation
MAX_LENGTH=30

# Function to get the status and metadata for a specific player and output JSON
get_player_info() {
    local PLAYER_ID=$1
    
    local STATUS
    STATUS=$(playerctl --player="$PLAYER_ID" status 2>/dev/null) || return 1
    
    if [[ "$STATUS" == "Playing" || "$STATUS" == "Paused" ]]; then
            
            local METADATA=$(playerctl --player="$PLAYER_ID" metadata --format '{{ artist }} - {{ title }}' 2>/dev/null)
            
            # Filter out common browser junk titles
            if [[ "$METADATA" == *"Echo360"* || "$METADATA" == *"YouTube"* || "$METADATA" == *"Vimeo"* ]]; then
                return 1
            fi
            
            if [ -n "$METADATA" ]; then
                
                # --- TRUNCATION LOGIC STARTS HERE ---
                local DISPLAY_TEXT="$METADATA"
                if [ ${#METADATA} -gt $MAX_LENGTH ]; then
                    # Truncate and add ellipsis (...)
                    DISPLAY_TEXT="${METADATA:0:$MAX_LENGTH}..."
                fi
                # --- TRUNCATION LOGIC ENDS HERE ---
                
                # Output JSON object with the (potentially truncated) song name and status information
                # The full METADATA is still used for the "tooltip"
                echo "$PLAYER_ID" > "$ACTIVE_PLAYER_FILE"
                jq -cn \
                    --arg text "$DISPLAY_TEXT" \
                    --arg tooltip "$METADATA ($PLAYER_ID $STATUS)" \
                    --arg alt "$STATUS" \
                    '{text:$text, tooltip:$tooltip, alt:$alt}'
                return 0
            fi
        fi
    return 1
}

ALL_PLAYERS=$(playerctl -l 2>/dev/null)

# 1. Loop through preferred desktop players first
for PLAYER in $PREFERRED_PLAYERS; do
    if get_player_info "$PLAYER"; then
        exit 0
    fi
done

# 2. If no preferred player is found, loop through ALL active players
for PLAYER in $ALL_PLAYERS; do
    if [[ "$PREFERRED_PLAYERS" != *"$PLAYER"* ]]; then
        if get_player_info "$PLAYER"; then
            exit 0
        fi
    fi
done

# Output nothing if no player is found
echo ""
