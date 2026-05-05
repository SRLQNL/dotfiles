#!/bin/bash

# Fallback: siempre imprime algo para comprobar
output=""

# Pide workspaces a niri
workspaces=$(niri msg --json workspaces | jq -r '.[] | "\(.idx) \(.active)"')

while read -r idx active; do
    icon="$idx"

    if [ "$active" = "true" ]; then
        output="$output[$icon] "
    else
        output="$output $icon  "
    fi
done <<< "$workspaces"

# Si no salió nada, imprimimos debug para que no quede vacío
if [ -z "$output" ]; then
    echo "⚠ no ws"
else
    echo "$output"
fi


