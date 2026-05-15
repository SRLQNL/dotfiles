#!/bin/bash
# Unit tests for toggle-large.sh detection logic.
# Run from any directory: bash test-toggle-large.sh
# No niri session needed — tests the branch-selection logic in isolation.

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "        expected='$expected'  got='$actual'"
        (( FAIL++ )) || true
    fi
}

# Mirrors the branch logic from toggle-large.sh.
# Args: IS_FLOATING OUTPUT_W OUTPUT_H TILE_W WIN_W WIN_H
detect_branch() {
    local IS_FLOATING="$1" OUTPUT_W="$2" OUTPUT_H="$3"
    local TILE_W_INT="$4" WIN_W="$5" WIN_H="$6"
    local THRESHOLD=$(( OUTPUT_W * 85 / 100 ))

    if [[ "$IS_FLOATING" != "true" ]] \
        && (( OUTPUT_W > 0 && OUTPUT_H > 0 )) \
        && (( WIN_W == OUTPUT_W && WIN_H == OUTPUT_H )); then
        echo "unfullscreen"
        return
    fi
    if [[ "$IS_FLOATING" == "true" ]]; then
        echo "float_to_tiling"
        return
    fi
    if (( TILE_W_INT >= THRESHOLD )); then
        echo "tiling_to_float"
        return
    fi
    echo "expand_to_full"
}

# Common output dimensions
OW=1920; OH=1080
# Tiling area: 1920 - 8*2(struts) - 12*2(gaps) = 1880; height varies with waybar
TW=1880; TH=1002

echo "=== toggle-large.sh logic tests ==="
echo ""

echo "-- Fullscreen detection --"
check "fullscreen: WIN==OUTPUT → unfullscreen" \
    "unfullscreen" "$(detect_branch false $OW $OH $OW $OW $OH)"
# REGRESSION #1: old code used tile_size == OUTPUT which fails because niri
# reports tile_size as tiling-area size (≈1880) even when fullscreen
check "regression#1: tile_size=tiling-area but WIN==OUTPUT → still unfullscreen" \
    "unfullscreen" "$(detect_branch false $OW $OH $TW $OW $OH)"

echo ""
echo "-- Tiling ↔ float --"
check "maximized tiling (tile=tiling-area, win=tiling-area) → float" \
    "tiling_to_float" "$(detect_branch false $OW $OH $TW $TW $TH)"
check "narrow tiling window → expand to full" \
    "expand_to_full" "$(detect_branch false $OW $OH 800 800 600)"
check "floating window → back to tiling" \
    "float_to_tiling" "$(detect_branch true $OW $OH 0 0 0)"

echo ""
echo "-- Edge cases --"
check "threshold boundary: exactly 85% wide → float" \
    "tiling_to_float" "$(detect_branch false $OW $OH $(( OW * 85 / 100 )) $(( OW * 85 / 100 )) 600)"
check "threshold boundary: 84% wide → expand" \
    "expand_to_full" "$(detect_branch false $OW $OH $(( OW * 84 / 100 )) $(( OW * 84 / 100 )) 600)"
check "zero output height only → fullscreen guard fails → check tile threshold" \
    "tiling_to_float" "$(detect_branch false $OW 0 $TW $OW $OH)"

echo ""
if (( FAIL == 0 )); then
    echo "All $PASS tests passed."
else
    echo "$PASS passed, $FAIL FAILED."
    exit 1
fi
