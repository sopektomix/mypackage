#!/bin/sh
# Copyright 2024-2025 sopeksemprit <www.sopeksemprit.xyz>
# QuotaLimiter - Per-device data quota limiter

. /lib/functions.sh

# Configuration
NAME="quotalimiter"
CONFIG="quotalimiter"
LOG_FILE="/var/log/quotalimiter.log"
DB_FILE="/var/lib/quotalimiter.db"
STATE_DIR="/var/run/quotalimiter"
COUNTERS_DIR="/tmp/quotalimiter"

# Default values
POLL_INTERVAL=30
FW_BACKEND="iptables"

mkdir -p "$STATE_DIR"
mkdir -p "$COUNTERS_DIR"

# Load config
load_config() {
    POLL_INTERVAL=$(uci get "$CONFIG".settings.poll_interval 2>/dev/null || echo "30")
    BACKEND=$(uci get "$CONFIG".settings.backend 2>/dev/null || echo "auto")
    LOG_FILE=$(uci get "$CONFIG".settings.log_file 2>/dev/null || echo "/var/log/quotalimiter.log")
    
    # Create log file if not exists
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # Detect backend
    if [ "$BACKEND" = "auto" ]; then
        if command -v nft >/dev/null 2>&1; then
            FW_BACKEND="nftables"
        else
            FW_BACKEND="iptables"
        fi
    else
        FW_BACKEND="$BACKEND"
    fi
}

# Logging
log_msg() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
    echo "$msg"  # Also echo to stdout for debugging
}

# Convert human to bytes
to_bytes() {
    local value="$1"
    local unit="$2"
    
    case "$unit" in
        GB) echo $((value * 1073741824)) ;;
        MB) echo $((value * 1048576)) ;;
        *)  echo "$value" ;;
    esac
}

# Initialize database
init_db() {
    if [ ! -f "$DB_FILE" ]; then
        echo "# ID|MAC|IP|LIMIT_BYTES|USED_BYTES|PERIOD|LAST_RESET|BLOCKED" > "$DB_FILE"
    fi
}

# Get device ID
get_device_id() {
    local mac="$1"
    local ip="$2"
    # Remove colons and dots for clean ID
    local clean_mac=$(echo "$mac" | tr -d ':')
    local clean_ip=$(echo "$ip" | tr -d '.')
    echo "${clean_mac}_${clean_ip}"
}

# Update usage counter
update_counter() {
    local id="$1"
    local bytes="$2"
    
    local counter_file="$COUNTERS_DIR/$id"
    local current=0
    
    if [ -f "$counter_file" ]; then
        current=$(cat "$counter_file" 2>/dev/null || echo 0)
    fi
    
    echo $((current + bytes)) > "$counter_file"
}

# Get current counter
get_counter() {
    local id="$1"
    
    if [ -f "$COUNTERS_DIR/$id" ]; then
        cat "$COUNTERS_DIR/$id" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# Reset counter
reset_counter() {
    local id="$1"
    echo 0 > "$COUNTERS_DIR/$id" 2>/dev/null
}

# Apply firewall block
apply_block() {
    local mac="$1"
    local ip="$2"
    
    log_msg "Applying block for $mac ($ip)"
    
    if [ "$FW_BACKEND" = "nftables" ]; then
        nft add rule inet fw4 forward ether saddr "$mac" drop 2>/dev/null && \
        nft add rule inet fw4 forward ip saddr "$ip" drop 2>/dev/null
    else
        iptables -I FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null && \
        iptables -I FORWARD -s "$ip" -j DROP 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        log_msg "Successfully blocked device: $mac ($ip)"
    else
        log_msg "Failed to block device: $mac ($ip)"
    fi
}

# Remove firewall block
remove_block() {
    local mac="$1"
    local ip="$2"
    
    log_msg "Removing block for $mac ($ip)"
    
    if [ "$FW_BACKEND" = "nftables" ]; then
        # Try multiple times to remove all matching rules
        for i in $(seq 1 5); do
            nft delete rule inet fw4 forward ether saddr "$mac" drop 2>/dev/null || true
            nft delete rule inet fw4 forward ip saddr "$ip" drop 2>/dev/null || true
        done
    else
        # Remove all matching rules
        while iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null; do :; done
        while iptables -D FORWARD -s "$ip" -j DROP 2>/dev/null; do :; done
    fi
}

# Check if device is blocked
is_blocked() {
    local mac="$1"
    
    if [ "$FW_BACKEND" = "nftables" ]; then
        nft list chain inet fw4 forward 2>/dev/null | grep -i "$mac" | grep -q "drop" && return 0
    else
        iptables -nL FORWARD 2>/dev/null | grep -i "$mac" | grep -q "DROP" && return 0
    fi
    
    return 1
}

# Update database
update_db() {
    local id="$1"
    local mac="$2"
    local ip="$3"
    local limit="$4"
    local used="$5"
    local period="$6"
    local blocked="$7"
    
    local today=$(date +%Y%m%d)
    local line="$id|$mac|$ip|$limit|$used|$period|$today|$blocked"
    
    # Remove old entry
    if [ -f "$DB_FILE" ]; then
        grep -v "^$id|" "$DB_FILE" > "${DB_FILE}.tmp" 2>/dev/null || true
        echo "$line" >> "${DB_FILE}.tmp"
        mv "${DB_FILE}.tmp" "$DB_FILE"
    else
        echo "$line" >> "$DB_FILE"
    fi
}

# Check if period needs reset
check_period_reset() {
    local last_reset="$1"
    local period="$2"
    local today=$(date +%Y%m%d)
    
    [ -z "$last_reset" ] && return 0
    [ "$last_reset" = "" ] && return 0
    
    case "$period" in
        hour)
            local current_hour=$(date +%Y%m%d%H)
            [ "$current_hour" != "$last_reset" ] && return 0
            ;;
        day)
            [ "$today" != "$last_reset" ] && return 0
            ;;
        week)
            local current_week=$(date +%Y%W)
            local last_week=$(date -d "$last_reset" +%Y%W 2>/dev/null || echo "0")
            [ "$current_week" != "$last_week" ] && return 0
            ;;
        month)
            local current_month=$(date +%Y%m)
            local last_month="${last_reset:0:6}"
            [ "$current_month" != "$last_month" ] && return 0
            ;;
        never)
            return 1  # Never reset automatically
            ;;
    esac
    
    return 1
}

# ========================================
# DEVICE DETECTION FUNCTIONS
# ========================================

# Detect reachable devices
detect_devices() {
    echo "# Format: IP|STATUS|HOSTNAME|MAC"
    
    # Try multiple methods to detect devices
    
    # Method 1: Use arp (most reliable)
    arp -n 2>/dev/null | while read line; do
        local ip=$(echo "$line" | awk '{print $1}')
        local mac=$(echo "$line" | awk '{print $3}')
        local flags=$(echo "$line" | awk '{print $2}')
        
        # Skip incomplete and IPv6
        if [ -n "$ip" ] && [ -n "$mac" ] && [ "$mac" != "(incomplete)" ] && [[ ! "$ip" =~ : ]]; then
            mac=$(echo "$mac" | tr '[:lower:]' '[:upper:]')
            
            # Determine status
            local status="UNKNOWN"
            if [ "$flags" = "0x2" ] || echo "$line" | grep -q "C"; then
                status="REACHABLE"
            else
                # Try ping
                if ping -c1 -W1 "$ip" >/dev/null 2>&1; then
                    status="REACHABLE"
                else
                    status="UNREACHABLE"
                fi
            fi
            
            # Get hostname
            local hostname="unknown"
            
            # Try DHCP leases
            for lease_file in /tmp/dhcp.leases /var/lib/misc/dnsmasq.leases; do
                if [ -f "$lease_file" ]; then
                    local lease=$(grep -i "$mac" "$lease_file" 2>/dev/null | head -1)
                    if [ -n "$lease" ]; then
                        hostname=$(echo "$lease" | awk '{print $4}')
                        if [ "$hostname" = "*" ] || [ -z "$hostname" ]; then
                            hostname="unknown"
                        else
                            if [[ ! "$hostname" =~ \.lan$ ]] && [[ ! "$hostname" =~ \.local$ ]]; then
                                hostname="${hostname}.lan"
                            fi
                            break
                        fi
                    fi
                fi
            done
            
            # Try nslookup
            if [ "$hostname" = "unknown" ] && command -v nslookup >/dev/null 2>&1; then
                local nslookup_result=$(nslookup "$ip" 2>/dev/null | grep "name =" | awk '{print $4}' | sed 's/\.$//')
                if [ -n "$nslookup_result" ]; then
                    hostname="$nslookup_result"
                fi
            fi
            
            echo "${ip}|${status}|${hostname}|${mac}"
        fi
    done
    
    # Method 2: Check active DHCP leases
    if [ -f "/tmp/dhcp.leases" ]; then
        cat "/tmp/dhcp.leases" | while read line; do
            local mac=$(echo "$line" | awk '{print $2}')
            local ip=$(echo "$line" | awk '{print $3}')
            local hostname=$(echo "$line" | awk '{print $4}')
            
            if [ -n "$mac" ] && [ -n "$ip" ] && [ "$hostname" != "*" ]; then
                mac=$(echo "$mac" | tr '[:lower:]' '[:upper:]')
                
                # Check if already listed
                if ! grep -q "$mac" /proc/net/arp 2>/dev/null; then
                    local status="UNREACHABLE"
                    if ping -c1 -W1 "$ip" >/dev/null 2>&1; then
                        status="REACHABLE"
                    fi
                    
                    if [ "$hostname" = "" ]; then
                        hostname="unknown"
                    else
                        if [[ ! "$hostname" =~ \.lan$ ]] && [[ ! "$hostname" =~ \.local$ ]]; then
                            hostname="${hostname}.lan"
                        fi
                    fi
                    
                    echo "${ip}|${status}|${hostname}|${mac}"
                fi
            fi
        done
    fi
}

# Process traffic - SIMPLIFIED VERSION
process_traffic() {
    # Simple simulation - in real implementation, use conntrack or iptables counters
    # For now, just simulate some traffic
    config_load "$CONFIG"
    config_foreach simulate_traffic quota
}

simulate_traffic() {
    local section="$1"
    
    config_get enabled "$section" enabled "0"
    [ "$enabled" = "0" ] && return
    
    config_get mac "$section" mac ""
    config_get ip "$section" ip ""
    
    [ -z "$mac" ] && [ -z "$ip" ] && return
    
    local device_id=$(get_device_id "$mac" "$ip")
    local current=$(get_counter "$device_id")
    
    # Simulate 1MB traffic every minute
    echo $((current + 1048576)) > "$COUNTERS_DIR/$device_id"
}

# Process rules
process_rules() {
    config_load "$CONFIG"
    
    config_foreach process_rule quota
}

process_rule() {
    local section="$1"
    
    config_get enabled "$section" enabled "0"
    [ "$enabled" = "0" ] && return
    
    config_get mac "$section" mac ""
    config_get ip "$section" ip ""
    config_get limit "$section" limit "1"
    config_get unit "$section" unit "GB"
    config_get period "$section" period "day"
    config_get comment "$section" comment ""
    
    [ -z "$mac" ] && [ -z "$ip" ] && return
    
    local device_id=$(get_device_id "$mac" "$ip")
    local limit_bytes=$(to_bytes "$limit" "$unit")
    local used_bytes=$(get_counter "$device_id")
    
    # Check if period needs reset
    local db_line=""
    local last_reset=""
    local blocked="0"
    
    if [ -f "$DB_FILE" ]; then
        db_line=$(grep "^$device_id|" "$DB_FILE" 2>/dev/null | tail -1)
    fi
    
    if [ -n "$db_line" ]; then
        last_reset=$(echo "$db_line" | cut -d'|' -f7)
        blocked=$(echo "$db_line" | cut -d'|' -f8)
        
        if check_period_reset "$last_reset" "$period"; then
            reset_counter "$device_id"
            used_bytes=0
            blocked="0"
            remove_block "$mac" "$ip"
            log_msg "Reset quota for $comment ($mac)"
        fi
    fi
    
    # Check if quota exceeded
    if [ "$used_bytes" -ge "$limit_bytes" ] && [ "$limit_bytes" -gt 0 ]; then
        if [ "$blocked" = "0" ]; then
            apply_block "$mac" "$ip"
            blocked="1"
            log_msg "Quota exceeded for $comment ($mac): ${used_bytes}/${limit_bytes}"
        fi
    else
        if [ "$blocked" = "1" ]; then
            remove_block "$mac" "$ip"
            blocked="0"
            log_msg "Quota restored for $comment ($mac): ${used_bytes}/${limit_bytes}"
        fi
    fi
    
    # Update database
    update_db "$device_id" "$mac" "$ip" "$limit_bytes" "$used_bytes" "$period" "$blocked"
}

# Get usage for specific device
get_usage() {
    local device_id="$1"
    
    if [ -f "$DB_FILE" ]; then
        local line=$(grep "^$device_id|" "$DB_FILE" 2>/dev/null | tail -1)
        if [ -n "$line" ]; then
            echo "$line" | cut -d'|' -f4,5,8
        else
            echo "0|0|0"
        fi
    else
        echo "0|0|0"
    fi
}

# Reset all quotas
reset_all() {
    log_msg "========== RESETTING ALL QUOTAS =========="
    
    # Clear counters
    rm -rf "$COUNTERS_DIR"
    mkdir -p "$COUNTERS_DIR"
    
    # Remove all blocks
    log_msg "Removing all firewall blocks..."
    
    if [ "$FW_BACKEND" = "nftables" ]; then
        nft flush chain inet fw4 forward 2>/dev/null || true
    else
        # Remove only DROP rules for our devices
        while iptables -D FORWARD -j DROP 2>/dev/null; do :; done
    fi
    
    # Reset database
    rm -f "$DB_FILE"
    init_db
    
    # Reset all device counters
    config_load "$CONFIG"
    config_foreach reset_device_counter quota
    
    log_msg "All quotas have been reset"
    echo "All quotas have been reset successfully"
}

reset_device_counter() {
    local section="$1"
    config_get mac "$section" mac ""
    config_get ip "$section" ip ""
    
    if [ -n "$mac" ] && [ -n "$ip" ]; then
        local device_id=$(get_device_id "$mac" "$ip")
        reset_counter "$device_id"
        log_msg "Reset counter for $mac ($ip)"
    fi
}

# Daemon main loop
daemon_main() {
    log_msg "========== STARTING QUOTALIMITER DAEMON =========="
    load_config
    init_db
    
    log_msg "Backend: $FW_BACKEND, Interval: ${POLL_INTERVAL}s"
    log_msg "Log file: $LOG_FILE"
    log_msg "DB file: $DB_FILE"
    
    # Initial processing
    process_rules
    
    while true; do
        log_msg "Processing cycle..."
        process_traffic
        process_rules
        sleep "$POLL_INTERVAL"
    done
}

# ========================================
# CLI COMMANDS
# ========================================
case "$1" in
    daemon)
        daemon_main
        ;;
    start)
        echo "Starting QuotaLimiter..."
        /etc/init.d/quotalimiter start
        ;;
    stop)
        echo "Stopping QuotaLimiter..."
        /etc/init.d/quotalimiter stop
        ;;
    restart)
        echo "Restarting QuotaLimiter..."
        /etc/init.d/quotalimiter restart
        ;;
    status)
        if pgrep -f "quotalimiter.sh daemon" >/dev/null; then
            echo "Running"
            echo "PID: $(pgrep -f "quotalimiter.sh daemon")"
            
            # Count devices
            local total=$(uci show quotalimiter 2>/dev/null | grep -c "=quota")
            local enabled=$(uci show quotalimiter 2>/dev/null | grep "enabled='1'" | grep -c "=quota")
            local blocked=0
            
            if [ "$FW_BACKEND" = "nftables" ]; then
                blocked=$(nft list chain inet fw4 forward 2>/dev/null | grep -c "drop")
            else
                blocked=$(iptables -nL FORWARD 2>/dev/null | grep -c "DROP")
            fi
            
            echo "Devices: $total total, $enabled enabled, $blocked blocked"
        else
            echo "Stopped"
        fi
        ;;
    devices|detect)
        detect_devices
        ;;
    usage)
        if [ -n "$2" ]; then
            get_usage "$2"
        else
            echo "Device Usage:"
            if [ -f "$DB_FILE" ]; then
                while IFS='|' read id mac ip limit used period last_reset blocked; do
                    if [ -n "$id" ] && [ "$id" != "# ID" ]; then
                        used_mb=$((used/1048576))
                        limit_mb=$((limit/1048576))
                        percent=0
                        if [ $limit -gt 0 ]; then
                            percent=$((used*100/limit))
                        fi
                        status="ACTIVE"
                        [ "$blocked" = "1" ] && status="BLOCKED"
                        echo "$mac ($ip): $used_mb/$limit_mb MB ($percent%) - $status"
                    fi
                done < "$DB_FILE"
            else
                echo "No usage data"
            fi
        fi
        ;;
    reset)
        reset_all
        ;;
    get_usage)
        get_usage "$2"
        ;;
    log)
        if [ "$2" = "clear" ]; then
            echo "" > "$LOG_FILE"
            echo "Log cleared"
        else
            if [ -f "$LOG_FILE" ]; then
                tail -50 "$LOG_FILE"
            else
                echo "Log file not found"
            fi
        fi
        ;;
    debug)
        echo "=== QuotaLimiter Debug Information ==="
        echo ""
        echo "1. Service Status:"
        /usr/bin/quotalimiter.sh status
        echo ""
        echo "2. Configuration:"
        uci show quotalimiter 2>/dev/null || echo "No config found"
        echo ""
        echo "3. Detected Devices:"
        detect_devices
        echo ""
        echo "4. Firewall Rules:"
        if command -v nft >/dev/null 2>&1; then
            nft list chain inet fw4 forward 2>/dev/null || echo "No nftables rules"
        else
            iptables -nL FORWARD 2>/dev/null | head -20
        fi
        echo ""
        echo "5. Database:"
        if [ -f "$DB_FILE" ]; then
            cat "$DB_FILE"
        else
            echo "No database file"
        fi
        echo ""
        echo "6. Log file: $LOG_FILE"
        if [ -f "$LOG_FILE" ]; then
            echo "Size: $(wc -l < "$LOG_FILE") lines"
            tail -5 "$LOG_FILE"
        else
            echo "Log file not found"
        fi
        ;;
    *)
        echo "QuotaLimiter v2.0"
        echo "Usage: $0 {daemon|start|stop|restart|status|devices|usage|reset|log|debug}"
        echo ""
        echo "Commands:"
        echo "  daemon        Run as daemon"
        echo "  start         Start service"
        echo "  stop          Stop service"
        echo "  restart       Restart service"
        echo "  status        Check service status"
        echo "  devices       List detected devices"
        echo "  usage         Show quota usage"
        echo "  reset         Reset all quotas"
        echo "  log           Show log (add 'clear' to clear)"
        echo "  debug         Show debug information"
        exit 1
        ;;
esac

exit 0
