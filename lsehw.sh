#!/bin/bash

RESET="\\e[0m"
BOLD="\\e[1m"
DIM="\\e[2m"
RED="\\e[1;31m"
GREEN="\\e[1;32m"
YELLOW="\\e[1;33m"
BLUE="\\e[1;34m"
MAGENTA="\\e[1;35m"
CYAN="\\e[1;36m"
WHITE="\\e[1;37m"

if [ "$(id -u 2>/dev/null)" != "0" ]; then
  echo -e "${RED}${BOLD}✖ Error:${RESET} Please run as root."
  exit 1
fi

echo -e ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║              ESSENTIAL SYSTEM HARDWARE LIST              ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo -e ""

# --- CPU INFO ---
echo -e "${BLUE}${BOLD}▶ 🖥️  PROCESSOR (CPU)${RESET}"
cpu_model=$(grep -m1 'model name' /proc/cpuinfo | awk -F': ' '{print $2}')
cpu_cores=$(lscpu -b -p=Core,Socket | grep -v '^#' | sort -u | wc -l)
cpu_threads=$(nproc)

is_invalid() { [[ -z "$1" || "$1" == "0" || "$1" == "0.0000" ]]; }

cpu_speed=$(lscpu | grep -i "CPU max MHz" | awk -F':' '{print $2}' | xargs)

if is_invalid "$cpu_speed"; then
    cpu_speed=$(lscpu | grep -i "CPU MHz" | awk -F':' '{print $2}' | xargs)
fi
if is_invalid "$cpu_speed"; then
    cpu_speed=$(awk '{printf "%.1f", $1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
fi
if is_invalid "$cpu_speed"; then
    cpu_speed=$(grep -m1 'cpu MHz' /proc/cpuinfo | awk -F': ' '{print $2}')
fi
if is_invalid "$cpu_speed"; then
    cpu_speed=$(dmidecode -t processor 2>/dev/null | grep -i "Max Speed" | grep -oE '[0-9]+' | head -n1)
fi

cpu_speed_int=$(printf "%.0f" "$cpu_speed" 2>/dev/null)
[ -z "$cpu_speed_int" ] || [ "$cpu_speed_int" = "0" ] && cpu_speed_int="Unknown"

echo -e "  ├─ ${BOLD}Model:${RESET}       ${WHITE}$cpu_model${RESET}"
echo -e "  ├─ ${BOLD}Cores:${RESET}       ${GREEN}$cpu_cores${RESET} Physical ${DIM}|${RESET} ${GREEN}$cpu_threads${RESET} Logical"
[[ "$cpu_speed_int" == "Unknown" ]] \
    && echo -e "  └─ ${BOLD}Speed:${RESET}       ${DIM}Unknown${RESET}" \
    || echo -e "  └─ ${BOLD}Speed:${RESET}       ${YELLOW}${cpu_speed_int} MHz${RESET}"
echo -e ""


# --- RAM INFO ---
echo -e "${MAGENTA}${BOLD}▶ 🧠 MEMORY (RAM)${RESET}"
ram_size=$(awk 'function ceil(x){return int(x)+(x>int(x))} /MemTotal/ {print ceil($2/1048576)}' /proc/meminfo)
ram_type=$(dmidecode -t memory | grep -E "Type: DDR" | head -n1 | awk -F': ' '{print $2}')
[ -z "$ram_type" ] && ram_type=$(dmidecode -t memory | grep "Type:" | grep -v -E "Error|Unknown" | head -n1 | awk -F': ' '{print $2}')
ram_speed=$(dmidecode -t memory | grep -E "Speed: [0-9]+ MT/s|Speed: [0-9]+ MHz" | head -n1 | awk -F': ' '{print $2}')

echo -e "  ├─ ${BOLD}Size:${RESET}        ${GREEN}${ram_size} GB${RESET}"
echo -e "  ├─ ${BOLD}DDR Version:${RESET} ${WHITE}${ram_type:-Unknown}${RESET}"
echo -e "  └─ ${BOLD}Speed:${RESET}       ${YELLOW}${ram_speed:-Unknown}${RESET}"
echo -e ""


# --- STORAGE DEVICES ---
echo -e "${YELLOW}${BOLD}▶ 💾 INTERNAL STORAGE DEVICES${RESET}"
lsblk -d -n -b -o NAME,SIZE,ROTA,TRAN | while read -r name bytes rota tran; do
    if [[ "$name" == loop* ]] || \
       [[ "$name" == sr* ]]   || \
       [[ "$name" == zram* ]] || \
       [[ "$name" == ram* ]]  || \
       [[ "$name" == fd* ]]   || \
       [[ "$tran" == "usb" ]]; then
        continue
    fi
    size_gb=$(awk -v b="$bytes" 'BEGIN {printf "%.0f GB", b/1000000000}')
    drive_type="Unknown"
    if [[ "$name" == nvme* ]] || [[ "$tran" == "nvme" ]]; then
        drive_type="NVMe SSD"; color=$CYAN
    elif [ "$rota" -eq 1 ]; then
        drive_type="HDD"; color=$YELLOW
    elif [ "$rota" -eq 0 ]; then
        drive_type="SATA SSD"; color=$GREEN
    fi
    echo -e "  ▪ ${BOLD}/dev/$name${RESET} ── ${WHITE}$size_gb${RESET} ${color}[$drive_type]${RESET}"
done
echo -e ""


# --- NETWORK INFO ---
echo -e "${BLUE}${BOLD}▶ 🌐 NETWORK${RESET}"

_wifi_standard() {
    local phy_info="$1"
    if echo "$phy_info" | grep -q "EHT Capa"; then
        echo "802.11be (Wi-Fi 7)"
    elif echo "$phy_info" | grep -q "HE PHY Capa"; then
        if echo "$phy_info" | grep -qP '\* (59[3-9]\d|[67]\d{3}) MHz'; then
            echo "802.11ax (Wi-Fi 6E)"
        else
            echo "802.11ax (Wi-Fi 6)"
        fi
    elif echo "$phy_info" | grep -q "VHT Capa"; then
        echo "802.11ac (Wi-Fi 5)"
    elif echo "$phy_info" | grep -q "HT Capa"; then
        echo "802.11n (Wi-Fi 4)"
    else
        echo "802.11a/b/g"
    fi
}

# --- Ethernet ---
eth_found=0
for iface in $(ls /sys/class/net/ 2>/dev/null | sort); do
    [[ "$iface" == "lo" ]] && continue
    [[ -d "/sys/class/net/$iface/wireless" ]] && continue
    [[ "$(cat /sys/class/net/$iface/type 2>/dev/null)" != "1" ]] && continue
    [[ ! -e "/sys/class/net/$iface/device" ]] && continue

    eth_found=1

    speed_raw=$(cat /sys/class/net/$iface/speed 2>/dev/null)
    if [[ -n "$speed_raw" && "$speed_raw" -gt 0 ]] 2>/dev/null; then
        if [[ "$speed_raw" -ge 1000 ]]; then
            speed_str="${speed_raw} Mbps  ($(( speed_raw / 1000 )) Gbps)"
        else
            speed_str="${speed_raw} Mbps"
        fi
        speed_color=$GREEN
    elif [[ "$speed_raw" == "-1" ]]; then
        speed_str="No carrier (cable unplugged?)"
        speed_color=$DIM
    else
        speed_str="Unknown"
        speed_color=$DIM
    fi

    local_ip=$(ip -4 addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
    mac=$(cat /sys/class/net/$iface/address 2>/dev/null)

    echo -e "  ├─ ${BOLD}ETH [${iface}]${RESET}"
    echo -e "  │   ├─ ${BOLD}MAC:${RESET}   ${DIM}${mac:-N/A}${RESET}"
    echo -e "  │   ├─ ${BOLD}IP:${RESET}    ${WHITE}${local_ip:-No IP assigned}${RESET}"
    echo -e "  │   └─ ${BOLD}Speed:${RESET} ${speed_color}${speed_str}${RESET}"
done
[[ "$eth_found" -eq 0 ]] && echo -e "  ├─ ${BOLD}Ethernet:${RESET}   ${DIM}No physical interfaces detected${RESET}"

bridge_found=0
for iface in $(ls /sys/class/net/ 2>/dev/null | sort); do
    [[ ! -d "/sys/class/net/$iface/bridge" ]] && continue
    bridge_found=1

    local_ip=$(ip -4 addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
    mac=$(cat /sys/class/net/$iface/address 2>/dev/null)

    slaves=$(ls /sys/class/net/$iface/brif/ 2>/dev/null | tr '\n' ' ')

    speed_raw=""
    for slave in $slaves; do
        s=$(cat /sys/class/net/$slave/speed 2>/dev/null)
        [[ -n "$s" && "$s" -gt 0 ]] 2>/dev/null && { speed_raw=$s; break; }
    done

    if [[ -n "$speed_raw" && "$speed_raw" -gt 0 ]] 2>/dev/null; then
        [[ "$speed_raw" -ge 1000 ]] \
            && speed_str="${speed_raw} Mbps  ($(( speed_raw / 1000 )) Gbps)" \
            || speed_str="${speed_raw} Mbps"
        speed_color=$GREEN
    else
        speed_str="Unknown"
        speed_color=$DIM
    fi

    echo -e "  ├─ ${BOLD}Bridge [${iface}]${RESET}  ${DIM}enslaves: ${slaves}${RESET}"
    echo -e "  │   ├─ ${BOLD}MAC:${RESET}   ${DIM}${mac:-N/A}${RESET}"
    echo -e "  │   ├─ ${BOLD}IP:${RESET}    ${WHITE}${local_ip:-No IP assigned}${RESET}"
    echo -e "  │   └─ ${BOLD}Speed:${RESET} ${speed_color}${speed_str}${RESET}"
done


# --- WiFi ---
wifi_found=0
for iface in $(ls /sys/class/net/ 2>/dev/null | sort); do
    [[ ! -d "/sys/class/net/$iface/wireless" ]] && continue
    wifi_found=1

    wifi_gen="Unknown"
    if command -v iw &>/dev/null; then
        phy_name=$(iw dev "$iface" info 2>/dev/null | awk '/wiphy/{print "phy"$2}')
        if [[ -n "$phy_name" ]]; then
            phy_info=$(iw "$phy_name" info 2>/dev/null)
            wifi_gen=$(_wifi_standard "$phy_info")
        fi
    fi

    ssid=$(iw dev "$iface" link 2>/dev/null | awk '/SSID:/{print $2}')
    freq=$(iw dev "$iface" link 2>/dev/null | awk '/freq:/{print $2, "MHz"}')
    tx_rate=$(iw dev "$iface" link 2>/dev/null | sed -n 's/.*tx bitrate: \([0-9.]* [A-Za-z/]*\).*/\1/p')
    rx_rate=$(iw dev "$iface" link 2>/dev/null | sed -n 's/.*rx bitrate: \([0-9.]* [A-Za-z/]*\).*/\1/p')
    local_ip=$(ip -4 addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
    mac=$(cat /sys/class/net/$iface/address 2>/dev/null)

    if [[ -n "$ssid" ]]; then
        conn_label="${WHITE}${ssid}${RESET}"
    else
        conn_label="${DIM}Not connected${RESET}"
    fi

    echo -e "  ├─ ${BOLD}WiFi [${iface}]${RESET}  SSID: ${conn_label}"
    echo -e "      ├─ ${BOLD}Standard:${RESET} ${YELLOW}${wifi_gen}${RESET}"
    echo -e "      ├─ ${BOLD}MAC:${RESET}      ${DIM}${mac:-N/A}${RESET}"
    echo -e "      ├─ ${BOLD}IP:${RESET}       ${WHITE}${local_ip:-No IP assigned}${RESET}"
    [[ -n "$freq" ]]    && echo -e "      ├─ ${BOLD}Freq:${RESET}     ${CYAN}${freq}${RESET}"
    [[ -n "$tx_rate" ]] && echo -e "      ├─ ${BOLD}TX Rate:${RESET}  ${GREEN}${tx_rate}${RESET}"
    if [[ -n "$rx_rate" ]]; then
        echo -e "      └─ ${BOLD}RX Rate:${RESET}  ${GREEN}${rx_rate}${RESET}"
    elif [[ -z "$ssid" ]]; then
        echo -e "      └─ ${BOLD}Link:${RESET}     ${DIM}No active connection${RESET}"
    fi
done
[[ "$wifi_found" -eq 0 ]] && echo -e "  └─ ${BOLD}WiFi:${RESET}       ${DIM}No wireless interfaces detected${RESET}"

echo -e ""


# --- GRAPHICS INFO ---
echo -e "${GREEN}${BOLD}▶ 🎮 GRAPHICS (GPU)${RESET}"

gpu_lines=()
while read -r line; do
    gpu_lines+=("$line")
done <<< "$(lspci | grep -iE 'VGA compatible controller|3D controller|Display controller')"

gpu_total=${#gpu_lines[@]}

if [[ "$gpu_total" -eq 0 || -z "${gpu_lines[0]}" ]]; then
    echo -e "  └─ ${DIM}No GPU detected${RESET}"
else
    for (( gi=0; gi<gpu_total; gi++ )); do
        line="${gpu_lines[$gi]}"
        gpu_model=$(echo "$line" | sed -E 's/.*(VGA compatible controller|3D controller|Display controller): //')
        pci_id=$(echo "$line" | awk '{print $1}')

        if (( gi == gpu_total - 1 )); then
            m_branch="  └─"
            s_prefix="      └─"
        else
            m_branch="  ├─"
            s_prefix="  │   └─"
        fi

        gpu_type="EXT"
        type_color=$CYAN
        if echo "$gpu_model" | grep -qiE "integrated|HD Graphics|UHD Graphics|Iris|Radeon.*Graphics|APU|G200|Matrox"; then
            gpu_type="Integrated"
            type_color=$YELLOW
        fi

        echo -e "${m_branch} ${BOLD}Model:${RESET} ${WHITE}$gpu_model${RESET}"

        if [[ "$gpu_type" == "EXT" ]]; then
            pcie_info=$(lspci -vv -s "$pci_id" 2>/dev/null | grep -i "LnkSta:")
            pcie_speed=$(echo "$pcie_info" | grep -oE 'Speed [0-9.]+GT/s' | awk '{print $2}')
            pcie_width=$(echo "$pcie_info" | grep -oE 'Width x[0-9]+' | awk '{print $2}')

            case "$pcie_speed" in
                2.5GT/s) pcie_gen="PCIe Gen 1" ;;
                5GT/s)   pcie_gen="PCIe Gen 2" ;;
                8GT/s)   pcie_gen="PCIe Gen 3" ;;
                16GT/s)  pcie_gen="PCIe Gen 4" ;;
                32GT/s)  pcie_gen="PCIe Gen 5" ;;
                64GT/s)  pcie_gen="PCIe Gen 6" ;;
                *)       pcie_gen="PCIe"        ;;
            esac

            if [[ -n "$pcie_speed" && -n "$pcie_width" ]]; then
                echo -e "${s_prefix} ${BOLD}Type:${RESET}  ${MAGENTA}${pcie_gen} ${pcie_width}${RESET} ${DIM}(${pcie_speed})${RESET}"
            elif [[ -n "$pcie_speed" ]]; then
                echo -e "${s_prefix} ${BOLD}Type:${RESET}  ${MAGENTA}${pcie_gen}${RESET} ${DIM}(${pcie_speed})${RESET}"
            else
                echo -e "${s_prefix} ${BOLD}Type:${RESET}  ${type_color}EXT${RESET} ${DIM}(PCIe info unavailable)${RESET}"
            fi
        else
            echo -e "${s_prefix} ${BOLD}Type:${RESET}  ${type_color}${gpu_type}${RESET}"
        fi
    done
fi
