#!/usr/bin/env bash

#
#  Hardware Info Report Script
#  功能: 检测并生成物理服务器的详细硬件信息报告，可自动安装缺失的依赖。
#  作者: DX
#  版本: 1.2.0 (增加了依赖自动安装功能)
#  依赖: bash, lscpu, free, dmidecode, df, lsblk, smartctl, lspci, ethtool, ip, lshw, jq
#  注意: 此脚本需要以 root 权限运行
#

# --- 前置检查 ---
if [[ $EUID -ne 0 ]]; then
   echo "错误：此脚本需要以 root 权限运行。"
   echo "请尝试使用: sudo bash $0"
   exit 1
fi

# --- 依赖自动安装 ---

# 定义依赖列表
DEPS_REQUIRED=(
    "lscpu:util-linux" "free:procps" "dmidecode:dmidecode" "df:coreutils" 
    "lsblk:util-linux" "smartctl:smartmontools" "lspci:pciutils" 
    "ethtool:ethtool" "ip:iproute2" "lshw:lshw" "jq:jq"
)

# 检查缺失的依赖
check_deps() {
    MISSING_PKGS=()
    echo "正在检查所需依赖..."
    for dep in "${DEPS_REQUIRED[@]}"; do
        CMD="${dep%%:*}"
        PKG="${dep##*:}"
        if ! command -v "$CMD" &> /dev/null; then
            # 聚合缺失的包名，避免重复安装
            if [[ ! " ${MISSING_PKGS[*]} " =~ " ${PKG} " ]]; then
                MISSING_PKGS+=("$PKG")
            fi
        fi
    done
}

# 初次检查
check_deps

# 如果有缺失的依赖，则尝试安装
if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
    echo "警告：检测到以下软件包缺失: ${MISSING_PKGS[*]}"
    echo "脚本将尝试自动为您安装。"
    
    # 倒计时，给用户取消的机会
    for i in {5..1}; do
        printf "在 %d 秒后开始安装... (按 Ctrl+C 取消)\r" "$i"
        sleep 1
    done
    echo ""

    if command -v apt-get &> /dev/null; then
        echo "检测到 Debian/Ubuntu 系统，正在使用 apt-get 进行安装..."
        apt-get update -y
        apt-get install -y "${MISSING_PKGS[@]}"
    elif command -v dnf &> /dev/null; then
        echo "检测到 CentOS/RHEL/Fedora 系统，正在使用 dnf 进行安装..."
        dnf install -y "${MISSING_PKGS[@]}"
    elif command -v yum &> /dev/null; then
        echo "检测到老版本 CentOS/RHEL 系统，正在使用 yum 进行安装..."
        yum install -y "${MISSING_PKGS[@]}"
    else
        echo "错误：未检测到支持的包管理器 (apt-get, dnf, yum)。请手动安装以下软件包: ${MISSING_PKGS[*]}"
        exit 1
    fi

    if [ $? -ne 0 ]; then
        echo "错误：包安装过程中发生错误。请检查您的网络连接或包管理器配置。"
        exit 1
    fi

    # 安装后再次检查
    echo "安装完成，正在重新验证依赖..."
    check_deps
    if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
        echo "错误：自动安装后，以下软件包仍然缺失: ${MISSING_PKGS[*]}"
        echo "请尝试手动安装后再次运行脚本。"
        exit 1
    else
        echo "所有依赖均已满足！"
    fi
fi


# --- 样式定义 ---
header_line="════════════════════════════════════════════════════════════════════════════════"
title_text="系统硬件信息报告"

print_header() {
    local title="$1"
    echo "┌─ $title"
    echo "├──────"
}

print_footer() {
    echo "└──────────────────────────────────────────────────"
}

print_kv() {
    printf "│ %-20s: %s\n" "$1" "$2"
}

# --- 功能函数 (与v1.1.0版本相同) ---

get_system_info() {
    print_header "系统信息"
    print_kv "主机名" "$(hostname)"
    local os_name=$(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"')
    print_kv "操作系统" "$os_name"
    print_kv "内核版本" "$(uname -r)"
    local uptime_str=$(uptime | sed -e 's/.*up //; s/,.*load average.*//')
    print_kv "运行时间" "$uptime_str"
    print_footer
}

get_cpu_info() {
    print_header "处理器信息"
    print_kv "型号" "$(lscpu | grep 'Model name:' | sed 's/.*:[[:space:]]*//' | head -n 1)"
    print_kv "核心数" "$(lscpu | grep '^Core(s) per socket:' | sed 's/.*:[[:space:]]*//')"
    print_kv "线程数" "$(lscpu | grep '^CPU(s):' | sed 's/.*:[[:space:]]*//')"
    local cpu_mhz=$(lscpu | grep -m 1 -E 'CPU max MHz|CPU MHz' | sed 's/.*:[[:space:]]*//')
    print_kv "频率" "${cpu_mhz:-N/A} MHz"
    local l3_cache=$(lscpu | grep 'L3 cache:' | sed -e 's/.*:[[:space:]]*//' -e 's/([^)]*)//g' | tr -d ' ')
    print_kv "缓存" "$l3_cache"
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    print_kv "使用率" "$cpu_usage"
    print_footer
}

get_mem_info() {
    print_header "内存信息"
    local mem_info=$(free -h | grep "Mem:")
    print_kv "总计" "$(echo "$mem_info" | awk '{print $2}')"
    print_kv "已用" "$(echo "$mem_info" | awk '{print $3}')"
    print_kv "可用" "$(echo "$mem_info" | awk '{print $7}')"

    echo "│"
    echo "│ Memory Modules:"
    echo "├────────────────────────────────────────────────────────────────────────────────────────────────────┤"
    printf "│ │ %-8s │ %-6s │ %-12s │ %-12s │ %-15s │ %-20s │\n" "大小" "类型" "频率" "制造商" "序列号" "型号"
    echo "├────────────────────────────────────────────────────────────────────────────────────────────────────┤"
    
    local mem_data
    mem_data=$(dmidecode -t memory)
    local blocks=$(echo "$mem_data" | grep -n "Memory Device" | cut -d: -f1)
    local block_starts=($blocks)
    local block_ends=()
    for ((i=0; i<${#block_starts[@]}-1; i++)); do
        block_ends+=($((block_starts[i+1]-1)))
    done
    block_ends+=("$(echo "$mem_data" | wc -l)")

    for ((i=0; i<${#block_starts[@]}; i++)); do
        block_content=$(echo "$mem_data" | sed -n "${block_starts[i]},${block_ends[i]}p")
        
        local size=$(echo "$block_content" | awk -F': ' '/^\s+Size:/ {print $2}')
        if [[ "$size" == "No Module Installed" ]]; then
            continue
        fi

        local type=$(echo "$block_content" | awk -F': ' '/^\s+Type:/ {print $2}')
        local speed=$(echo "$block_content" | awk -F': ' '/^\s+Speed:/ {print $2}')
        local manufacturer=$(echo "$block_content" | awk -F': ' '/^\s+Manufacturer:/ {print $2}')
        local serial=$(echo "$block_content" | awk -F': ' '/^\s+Serial Number:/ {print $2}')
        local part=$(echo "$block_content" | awk -F': ' '/^\s+Part Number:/ {print $2}')

        printf "│ │ %-8s │ %-6s │ %-12s │ %-12s │ %-15s │ %-20s │\n" "${size:-N/A}" "${type:-N/A}" "${speed:-N/A}" "${manufacturer:-N/A}" "${serial:-N/A}" "${part:-N/A}"
    done
    
    echo "└────────────────────────────────────────────────────────────────────────────────────────────────────┘"
    print_footer
}


get_disk_info() {
    print_header "硬盘信息"
    df -hT | grep -E "^/dev/(sd|nvme|vd)" | awk '{printf "│ %-15s %-5s %-5s %-5s %-4s %-s\n", $1, $3, $4, $5, $7, $8}'
    echo "│"
    echo "│ Physical Disks Details:"
    
    local disks=$(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}')
    for disk in $disks; do
        echo "││ ═══ /dev/$disk ═══"
        
        if ! smartctl -i "/dev/$disk" &> /dev/null; then
            echo "│   无法获取 /dev/$disk 的SMART信息 (可能不支持或权限问题)。"
            continue
        fi
        
        local smart_output=$(smartctl -A -i -H --json=o "/dev/$disk")
        
        local size_bytes=$(echo "$smart_output" | jq -r '.user_capacity.bytes // 0')
        local size_hr=$(numfmt --to=iec --suffix=B --format="%.1f" "$size_bytes" | sed 's/\.0//')
        local model=$(echo "$smart_output" | jq -r '.model_name // "N/A"')
        printf "│   %-15s %s %s\n" "Basic Info:" "$size_hr" "$model"

        local smart_status=$(echo "$smart_output" | jq -r '.smart_status.passed | if . then "PASSED" else "FAILED" end')
        printf "│   %-15s %s\n" "SMART状态:" "$smart_status"
        
        local power_on_hours=$(echo "$smart_output" | jq -r '.power_on_time.hours // "N/A"')
        printf "│   %-15s %s hours\n" "通电时间:" "$power_on_hours"

        local is_nvme=$(echo "$smart_output" | jq -r '.nvme_smart_health_information_log != null')
        if [[ "$is_nvme" == "true" ]]; then
            local read_bytes=$(echo "$smart_output" | jq -r '(.nvme_smart_health_information_log.data_units_read // 0) * 512 * 1000')
            local write_bytes=$(echo "$smart_output" | jq -r '(.nvme_smart_health_information_log.data_units_written // 0) * 512 * 1000')
            printf "│   Data Transfer Statistics:\n"
            printf "│     %-15s %s (SMART硬件累计)\n" "总读取量:" "$(numfmt --to=iec --suffix=B --format="%.3f" "$read_bytes")"
            printf "│     %-15s %s (SMART硬件累计)\n" "总写入量:" "$(numfmt --to=iec --suffix=B --format="%.3f" "$write_bytes")"
            local wear=$(echo "$smart_output" | jq -r '.nvme_smart_health_information_log.percentage_used // "N/A"')
            printf "│   %-15s %s%%\n" "磨损程度:" "$wear"
        else
            local read_lba=$(echo "$smart_output" | jq -r '.ata_smart_attributes.table[] | select(.id == 242) | .raw.value // 0')
            local write_lba=$(echo "$smart_output" | jq -r '.ata_smart_attributes.table[] | select(.id == 241) | .raw.value // 0')
            local read_bytes=$((read_lba * 512))
            local write_bytes=$((write_lba * 512))
            printf "│   Data Transfer Statistics:\n"
            printf "│     %-15s %s (SMART硬件累计)\n" "总读取量:" "$(numfmt --to=iec --suffix=B --format="%.3f" "$read_bytes")"
            printf "│     %-15s %s (SMART硬件累计)\n" "总写入量:" "$(numfmt --to=iec --suffix=B --format="%.3f" "$write_bytes")"
            local wear=$(echo "$smart_output" | jq -r '.ata_smart_attributes.table[] | select(.id == 233 or .id == 173) | .raw.value // "N/A"')
            printf "│   %-15s %s (原始值, 具体含义需查阅硬盘手册)\n" "磨损相关值:" "$wear"
        fi

        local temp=$(echo "$smart_output" | jq -r '.temperature.current // "N/A"')
        printf "│   %-15s %s°C\n" "温度:" "$temp"

    done
    print_footer
}

get_net_info() {
    print_header "网卡信息"
    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
    for iface in $interfaces; do
        echo "│"
        echo "│ ═══ $iface ═══"
        
        local pci_addr=$(ethtool -i "$iface" 2>/dev/null | grep "bus-info" | awk '{print $2}')
        local model="N/A"
        if [ -n "$pci_addr" ]; then
            model=$(lspci -s "$pci_addr" | cut -d':' -f3- | sed 's/^[ \t]*//')
        fi
        print_kv "型号" "$model"
        
        local status=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null | tr '[:lower:]' '[:upper:]')
        print_kv "状态" "$status"
        
        local ipv4=$(ip -4 addr show "$iface" | grep "inet" | awk '{print $2}')
        print_kv "IPv4" "${ipv4:-N/A}"
        
        local ipv6_addrs=$(ip -6 addr show "$iface" | grep "inet6" | awk '{print $2}')
        if [ -n "$ipv6_addrs" ]; then
            local first_ipv6=$(echo "$ipv6_addrs" | head -n1)
            local rest_ipv6=$(echo "$ipv6_addrs" | tail -n +2)
            print_kv "IPv6" "$first_ipv6"
            for ip6 in $rest_ipv6; do
                printf "│ %-20s  %s\n" "" "$ip6"
            done
        else
            print_kv "IPv6" "N/A"
        fi
        
        local mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
        print_kv "MAC地址" "$mac"
        
        local ethtool_info=$(ethtool "$iface" 2>/dev/null)
        local speed=$(echo "$ethtool_info" | grep "Speed:" | awk '{print $2}')
        local duplex=$(echo "$ethtool_info" | grep "Duplex:" | awk '{print $2}')
        local link_detected=$(echo "$ethtool_info" | grep "Link detected:" | awk '{print $3}')
        print_kv "速度" "${speed:-N/A}"
        print_kv "双工模式" "${duplex:-N/A}"
        print_kv "链接检测" "${link_detected:-N/A}"
        
        local rx_bytes=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null)
        local tx_bytes=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null)
        print_kv "RX" "$(numfmt --to=iec --suffix=B --format="%.2f" "$rx_bytes")"
        print_kv "TX" "$(numfmt --to=iec --suffix=B --format="%.2f" "$tx_bytes")"
    done
    print_footer
}

get_raid_info() {
    local raid_controllers=$(lspci | grep -i "RAID bus controller")
    if [ -n "$raid_controllers" ]; then
        print_header "RAID控制器信息"
        echo "│ Hardware RAID Controllers:"
        while read -r line; do
            echo "│   $line"
        done <<< "$raid_controllers"
        print_footer
    fi
}

get_gpu_info() {
    local gpus=$(lspci | grep -i "VGA compatible controller")
     if [ -n "$gpus" ]; then
        print_header "显卡信息"
        echo "│ Graphics Cards (PCI):"
        while read -r line; do
            echo "│   $line"
        done <<< "$gpus"
        
        local lshw_disp=$(lshw -C display 2>/dev/null)
        if [ -n "$lshw_disp" ]; then
            echo "│"
            echo "│ Display Hardware Summary:"
            echo "│   ============================================================"
            echo "$lshw_disp" | grep -E "description:|product:|vendor:|physical id:|bus info:|width:|clock:|capabilities:|configuration:|resources:" | sed 's/^/│   /'
        fi
        print_footer
    fi
}

get_board_info() {
    print_header "主板信息"
    print_kv "厂商" "$(dmidecode -s baseboard-manufacturer)"
    print_kv "型号" "$(dmidecode -s baseboard-product-name)"
    print_kv "Version" "$(dmidecode -s baseboard-version)"
    echo "│"
    print_kv "BIOS Vendor" "$(dmidecode -s bios-vendor)"
    print_kv "BIOS Version" "$(dmidecode -s bios-version)"
    print_footer
}


# --- 主程序 ---
clear
echo "$header_line"
printf "%*s\n" $(( (${#header_line} + ${#title_text}) / 2 )) "$title_text"
echo "$header_line"

# 依次调用函数
get_system_info
get_cpu_info
get_mem_info
get_disk_info
get_raid_info
get_net_info
get_gpu_info
get_board_info

echo "报告生成完成！"
echo "Generated on: $(date)"
