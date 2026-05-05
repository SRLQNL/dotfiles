#!/bin/bash

# Kill leftover processes from previous session
killall -9 waybar 2>/dev/null
killall -9 cava   2>/dev/null
sleep 0.3

# Wait for PipeWire pulse socket (pipewire-pulse provides PA compat)
for i in $(seq 1 20); do
    [ -S /run/user/1000/pulse/native ] && break
    sleep 0.5
done

# Wait for niri IPC socket (up to 10 seconds)
for i in $(seq 1 20); do
    NIRI_SOCKET=$(ls /run/user/1000/niri.*.sock 2>/dev/null | head -1)
    [ -n "$NIRI_SOCKET" ] && break
    sleep 0.5
done
export NIRI_SOCKET

exec waybar
