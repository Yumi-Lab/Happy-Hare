#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# YUMiLab YMS — Happy Hare Installer (non-interactive)
# Installs Happy Hare configured for YUMI YMS multi-color system
#
# Usage: ./install_yms.sh [options]
#   -n <num_gates>  Number of YMS gates (default: auto-detect from printer.cfg)
#   -s              Skip service restart
#   -d              Uninstall
#   -h              Show help
# ═══════════════════════════════════════════════════════════════════════
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[YMS]${NC} $1"; }
warn()  { echo -e "${YELLOW}[YMS]${NC} $1"; }
error() { echo -e "${RED}[YMS]${NC} $1"; }

# ── Paths ──────────────────────────────────────────────────────────────
SRCDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KLIPPER_HOME="${HOME}/klipper"
MOONRAKER_HOME="${HOME}/moonraker"
CONFIG_HOME="${HOME}/printer_data/config"
PRINTER_CFG="${CONFIG_HOME}/printer.cfg"

NUM_GATES=""
SKIP_RESTART=0
UNINSTALL=0

# ── Parse args ─────────────────────────────────────────────────────────
while getopts "n:sdh" arg; do
    case $arg in
        n) NUM_GATES=${OPTARG};;
        s) SKIP_RESTART=1;;
        d) UNINSTALL=1;;
        h) echo "Usage: $0 [-n num_gates] [-s] [-d] [-h]"
           echo "  -n  Number of YMS gates (default: auto-detect)"
           echo "  -s  Skip service restart"
           echo "  -d  Uninstall"
           exit 0;;
        *) echo "Unknown option: -${arg}"; exit 1;;
    esac
done

# ── Auto-detect gates ──────────────────────────────────────────────────
auto_detect_gates() {
    if [ -f "${PRINTER_CFG}" ]; then
        local count=0
        for i in $(seq 0 11); do
            if grep -q "^\[extruder_stepper extruder${i}\]" "${PRINTER_CFG}"; then
                count=$((count + 1))
            fi
        done
        echo $count
    else
        echo 0
    fi
}

if [ -z "${NUM_GATES}" ]; then
    NUM_GATES=$(auto_detect_gates)
    if [ "${NUM_GATES}" -eq 0 ]; then
        error "No extruder_stepper sections found in printer.cfg. Use -n to specify gate count."
        exit 1
    fi
    info "Auto-detected ${NUM_GATES} YMS gates from printer.cfg"
else
    info "Using ${NUM_GATES} YMS gates (manual)"
fi

# ── Uninstall ──────────────────────────────────────────────────────────
if [ "${UNINSTALL}" -eq 1 ]; then
    warn "Uninstalling Happy Hare YMS..."

    # Remove Klipper extensions
    if [ -d "${KLIPPER_HOME}/klippy/extras/mmu" ]; then
        rm -rf "${KLIPPER_HOME}/klippy/extras/mmu"
        for file in ${SRCDIR}/extras/*.py; do
            rm -f "${KLIPPER_HOME}/klippy/extras/$(basename "$file")"
        done
        info "Removed Klipper extensions"
    fi

    # Remove Moonraker extensions
    if [ -d "${MOONRAKER_HOME}/moonraker/components" ]; then
        for file in ${SRCDIR}/components/*.py; do
            rm -f "${MOONRAKER_HOME}/moonraker/components/$(basename "$file")"
        done
        info "Removed Moonraker extensions"
    fi

    # Remove config
    if [ -d "${CONFIG_HOME}/mmu" ]; then
        rm -rf "${CONFIG_HOME}/mmu"
        info "Removed MMU config directory"
    fi

    info "Uninstall complete. Remove [include mmu/base/*.cfg] from printer.cfg manually."
    exit 0
fi

# ── Verify paths ───────────────────────────────────────────────────────
verify_paths() {
    local ok=1
    [ ! -d "${KLIPPER_HOME}/klippy/extras" ] && { error "Klipper not found at ${KLIPPER_HOME}"; ok=0; }
    [ ! -d "${MOONRAKER_HOME}/moonraker/components" ] && { error "Moonraker not found at ${MOONRAKER_HOME}"; ok=0; }
    [ ! -d "${CONFIG_HOME}" ] && { error "Config dir not found at ${CONFIG_HOME}"; ok=0; }
    [ ! -f "${PRINTER_CFG}" ] && { error "printer.cfg not found"; ok=0; }
    [ $ok -eq 0 ] && exit 1
}

verify_paths
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   YUMiLab YMS — Happy Hare Installation      ║${NC}"
echo -e "${CYAN}║   Gates: ${NUM_GATES}                                    ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Step 1: Link Python extensions
# ══════════════════════════════════════════════════════════════════════
info "Step 1/5 — Linking Klipper extensions..."
mkdir -p "${KLIPPER_HOME}/klippy/extras/mmu"
for file in ${SRCDIR}/extras/*.py; do
    ln -sf "$file" "${KLIPPER_HOME}/klippy/extras/$(basename "$file")"
done
for file in ${SRCDIR}/extras/mmu/*.py; do
    ln -sf "$file" "${KLIPPER_HOME}/klippy/extras/mmu/$(basename "$file")"
done

info "Step 1/5 — Linking Moonraker extensions..."
for file in ${SRCDIR}/components/*.py; do
    ln -sf "$file" "${MOONRAKER_HOME}/moonraker/components/$(basename "$file")"
done

# ══════════════════════════════════════════════════════════════════════
# Step 2: Copy base config files
# ══════════════════════════════════════════════════════════════════════
info "Step 2/5 — Copying config files..."
mkdir -p "${CONFIG_HOME}/mmu/base"
mkdir -p "${CONFIG_HOME}/mmu/optional"

# Copy all base configs EXCEPT hardware (we generate our own)
for file in ${SRCDIR}/config/base/*.cfg; do
    base=$(basename "$file")
    case "$base" in
        *.kms|*.vvd|*.rs|*.ss|*.vs) continue ;;  # Skip vendor-specific alternates
        mmu_hardware.cfg) continue ;;              # Skip — we generate YMS-specific
        mmu.cfg) continue ;;                       # Skip — we generate YMS-specific
    esac
    cp "$file" "${CONFIG_HOME}/mmu/base/${base}"
done

# Copy optional
for file in ${SRCDIR}/config/optional/*.cfg; do
    cp "$file" "${CONFIG_HOME}/mmu/optional/$(basename "$file")"
done

# Copy mmu_vars
cp "${SRCDIR}/config/mmu_vars.cfg" "${CONFIG_HOME}/mmu/mmu_vars.cfg"

# ══════════════════════════════════════════════════════════════════════
# Step 3: Generate mmu.cfg for YMS
# ══════════════════════════════════════════════════════════════════════
info "Step 3/5 — Generating mmu.cfg for YUMI YMS (${NUM_GATES} gates)..."

cat > "${CONFIG_HOME}/mmu/base/mmu.cfg" << MMUCFG
# ═══════════════════════════════════════════════════════════════════════
# YUMiLab YMS — Happy Hare MMU Machine Configuration
# Auto-generated by install_yms.sh — ${NUM_GATES} gates
# ═══════════════════════════════════════════════════════════════════════

[mmu_machine]
num_gates: ${NUM_GATES}
mmu_vendor: YUMI
mmu_version: 1.0
selector_type: VirtualSelector
variable_rotation_distances: 1
variable_bowden_lengths: 0
require_bowden_move: 1
filament_always_gripped: 1
can_crossload: 1
has_bypass: 0
MMUCFG

info "  Created mmu.cfg"

# ══════════════════════════════════════════════════════════════════════
# Step 4: Generate mmu_hardware.cfg from printer.cfg pins
# ══════════════════════════════════════════════════════════════════════
info "Step 4/5 — Generating mmu_hardware.cfg from printer.cfg..."

# Extract pin mappings from existing extruder_stepper sections
extract_stepper_pins() {
    local idx=$1
    local section="extruder_stepper extruder${idx}"

    # Extract pins from printer.cfg
    local step_pin=$(sed -n "/^\[${section}\]/,/^\[/{ s/^step_pin: *//p; }" "${PRINTER_CFG}" | head -1)
    local dir_pin=$(sed -n "/^\[${section}\]/,/^\[/{ s/^dir_pin: *//p; }" "${PRINTER_CFG}" | head -1)
    local enable_pin=$(sed -n "/^\[${section}\]/,/^\[/{ s/^enable_pin: *//p; }" "${PRINTER_CFG}" | head -1)
    local rotation=$(sed -n "/^\[${section}\]/,/^\[/{ s/^rotation_distance: *//p; }" "${PRINTER_CFG}" | head -1)
    local gear_ratio=$(sed -n "/^\[${section}\]/,/^\[/{ s/^gear_ratio: *//p; }" "${PRINTER_CFG}" | head -1)
    local microsteps=$(sed -n "/^\[${section}\]/,/^\[/{ s/^microsteps: *//p; }" "${PRINTER_CFG}" | head -1)

    # Extract TMC pins
    local tmc_section="tmc2209 ${section}"
    local uart_pin=$(sed -n "/^\[${tmc_section}\]/,/^\[/{ s/^uart_pin: *//p; }" "${PRINTER_CFG}" | head -1)
    local run_current=$(sed -n "/^\[${tmc_section}\]/,/^\[/{ s/^run_current: *//p; }" "${PRINTER_CFG}" | head -1)
    local hold_current=$(sed -n "/^\[${tmc_section}\]/,/^\[/{ s/^hold_current: *//p; }" "${PRINTER_CFG}" | head -1)

    # Strip inline comments
    rotation=$(echo "$rotation" | sed 's/ *#.*//')
    gear_ratio=$(echo "$gear_ratio" | sed 's/ *#.*//')
    microsteps=$(echo "$microsteps" | sed 's/ *#.*//')
    run_current=$(echo "$run_current" | sed 's/ *#.*//')
    hold_current=$(echo "$hold_current" | sed 's/ *#.*//')

    echo "${step_pin}|${dir_pin}|${enable_pin}|${rotation}|${gear_ratio}|${microsteps}|${uart_pin}|${run_current}|${hold_current}"
}

# Start generating hardware config
HW_CFG="${CONFIG_HOME}/mmu/base/mmu_hardware.cfg"

cat > "${HW_CFG}" << 'HWHEADER'
# ═══════════════════════════════════════════════════════════════════════
# YUMiLab YMS — Happy Hare Hardware Configuration
# Auto-generated by install_yms.sh
#
# IMPORTANT: This file maps Happy Hare gear steppers to YMS extruder pins.
# The [extruder_stepper extruderN] sections in printer.cfg must be DISABLED
# when using Happy Hare (Happy Hare manages the gear steppers directly).
# ═══════════════════════════════════════════════════════════════════════

# No dedicated MMU MCU — YMS uses the printer's main MCU + SmartBox
# No selector stepper — YMS uses VirtualSelector (direct multi-gear)
# No servo — YMS has no filament grip mechanism
# No encoder — YMS uses filament motion sensors per gate

HWHEADER

# Generate each gear stepper
for i in $(seq 0 $((NUM_GATES - 1))); do
    pins=$(extract_stepper_pins $i)
    IFS='|' read -r step_pin dir_pin enable_pin rotation gear_ratio microsteps uart_pin run_current hold_current <<< "$pins"

    if [ -z "$step_pin" ]; then
        warn "  Gate ${i}: no pins found for extruder_stepper extruder${i}, skipping"
        continue
    fi

    # Gear stepper suffix (first one has no suffix)
    if [ $i -eq 0 ]; then
        suffix=""
    else
        suffix="_${i}"
    fi

    cat >> "${HW_CFG}" << GEARBLOCK
# ── YMS Gate ${i} (extruder${i}) ──────────────────────────────────────
[tmc2209 stepper_mmu_gear${suffix}]
uart_pin: ${uart_pin}
run_current: ${run_current:-0.7}
hold_current: ${hold_current:-0.1}
interpolate: True
sense_resistor: 0.110
stealthchop_threshold: 0

[stepper_mmu_gear${suffix}]
step_pin: ${step_pin}
dir_pin: ${dir_pin}
enable_pin: ${enable_pin}
rotation_distance: ${rotation:-22.6789511}
gear_ratio: ${gear_ratio:-50:17}
microsteps: ${microsteps:-16}
full_steps_per_rotation: 200

GEARBLOCK
    info "  Gate ${i}: step=${step_pin} uart=${uart_pin}"
done

# Add gate sensor section (map existing filament sensors)
cat >> "${HW_CFG}" << 'SENSORBLOCK'

# ── Gate Sensors ───────────────────────────────────────────────────────
# Happy Hare can use existing filament_motion_sensor definitions.
# Gate sensors are detected by name pattern: mmu_gate, mmu_gate_1, etc.
# For YMS, the existing YMS-N filament sensors serve this role.
# TODO: Map YMS-N sensors to mmu_gate sensor names or configure in mmu_parameters.cfg

SENSORBLOCK

info "  Hardware config generated: ${HW_CFG}"

# ══════════════════════════════════════════════════════════════════════
# Step 5: Configure mmu_parameters.cfg
# ══════════════════════════════════════════════════════════════════════
info "Step 5/5 — Configuring mmu_parameters.cfg..."

PARAMS="${CONFIG_HOME}/mmu/base/mmu_parameters.cfg"
if [ -f "$PARAMS" ]; then
    # YMS-specific parameter overrides
    sed -i 's/^extruder_homing_endstop:.*/extruder_homing_endstop: none/' "$PARAMS"
    sed -i 's/^gate_homing_endstop:.*/gate_homing_endstop: mmu_gate/' "$PARAMS"
    sed -i 's/^gate_homing_max:.*/gate_homing_max: 300/' "$PARAMS"
    sed -i 's/^gate_parking_distance:.*/gate_parking_distance: 100/' "$PARAMS"
    sed -i 's/^gate_final_eject_distance:.*/gate_final_eject_distance: 100/' "$PARAMS"
    sed -i 's/^sync_feedback_enabled:.*/sync_feedback_enabled: 1/' "$PARAMS"

    # Set default gate colors for visual UI (rainbow for now)
    COLORS=""
    NAMES=""
    MATERIALS=""
    for i in $(seq 1 ${NUM_GATES}); do
        case $((i % 7)) in
            1) COLORS="${COLORS}ff0000, ";  NAMES="${NAMES}YMS-${i}, ";  MATERIALS="${MATERIALS}PLA, " ;;
            2) COLORS="${COLORS}ff8800, ";  NAMES="${NAMES}YMS-${i}, ";  MATERIALS="${MATERIALS}PLA, " ;;
            3) COLORS="${COLORS}ffff00, ";  NAMES="${NAMES}YMS-${i}, ";  MATERIALS="${MATERIALS}PLA, " ;;
            4) COLORS="${COLORS}00ff00, ";  NAMES="${NAMES}YMS-${i}, ";  MATERIALS="${MATERIALS}PLA, " ;;
            5) COLORS="${COLORS}0088ff, ";  NAMES="${NAMES}YMS-${i}, ";  MATERIALS="${MATERIALS}PLA, " ;;
            6) COLORS="${COLORS}8800ff, ";  NAMES="${NAMES}YMS-${i}, ";  MATERIALS="${MATERIALS}PLA, " ;;
            0) COLORS="${COLORS}ff00ff, ";  NAMES="${NAMES}YMS-${i}, ";  MATERIALS="${MATERIALS}PLA, " ;;
        esac
    done
    # Remove trailing ", "
    COLORS=$(echo "$COLORS" | sed 's/, $//')
    NAMES=$(echo "$NAMES" | sed 's/, $//')
    MATERIALS=$(echo "$MATERIALS" | sed 's/, $//')

    sed -i "s/^gate_color:.*/gate_color: ${COLORS}/" "$PARAMS"
    sed -i "s/^gate_filament_name:.*/gate_filament_name: ${NAMES}/" "$PARAMS"
    sed -i "s/^gate_material:.*/gate_material: ${MATERIALS}/" "$PARAMS"

    info "  Parameters configured with ${NUM_GATES} gates and rainbow colors"
fi

# ══════════════════════════════════════════════════════════════════════
# Step 6: Install Moonraker update manager
# ══════════════════════════════════════════════════════════════════════
MOONRAKER_CONF="${CONFIG_HOME}/moonraker.conf"
if [ -f "${MOONRAKER_CONF}" ]; then
    if ! grep -q "update_manager happy-hare" "${MOONRAKER_CONF}"; then
        cat >> "${MOONRAKER_CONF}" << UPDMGR

[update_manager happy-hare]
type: git_repo
path: ~/Happy-Hare
origin: https://github.com/Yumi-Lab/Happy-Hare.git
primary_branch: yms-support
install_script: install_yms.sh
managed_services: klipper
UPDMGR
        info "  Added update_manager to moonraker.conf"
    else
        info "  update_manager already present in moonraker.conf"
    fi
fi

# ══════════════════════════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN} YUMiLab YMS — Happy Hare installed successfully!${NC}"
echo -e "${GREEN} Gates: ${NUM_GATES} | Vendor: YUMI | Selector: Virtual${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
warn "IMPORTANT: Before restarting Klipper, you must:"
warn "  1. Comment out [extruder_stepper extruderN] sections in printer.cfg"
warn "     (Happy Hare now manages these steppers as stepper_mmu_gear_N)"
warn "  2. Comment out [tmc2209 extruder_stepper extruderN] sections"
warn "  3. Add to printer.cfg:"
warn "       [include mmu/base/*.cfg]"
warn "       [include mmu/optional/client_macros.cfg]"
warn ""

if [ "${SKIP_RESTART}" -eq 0 ]; then
    warn "Skipping auto-restart — manual config changes needed first."
fi
