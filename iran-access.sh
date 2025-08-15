#!/bin/bash

#================================================================
# Firewall Manager Script for Ubuntu
# Author: Gemini
# Description: Manages iptables rules to restrict access based on an IP whitelist.
#================================================================

# --- Internal Variables ---
CONFIG_DIR="/etc/firewall_manager"
BACKUP_FILE="$CONFIG_DIR/iptables-backup.rules"
WHITELIST_FILE="$CONFIG_DIR/firewall.txt"
IPSET_NAME="whitelist_set"
IRAN_IP_LIST_URL="https://raw.githubusercontent.com/herrbischoff/country-ip-blocks/master/ipv4/ir.cidr"

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Functions ---

# Function to check for root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}خطا: این اسکریپت باید با دسترسی root اجرا شود. (sudo ./firewall_manager.sh)${NC}"
        exit 1
    fi
}

# Function to install necessary packages
install_dependencies() {
    echo -e "${YELLOW}بررسی و نصب بسته‌های مورد نیاز (iptables, ipset, iptables-persistent)...${NC}"
    # Pre-configure debconf to avoid interactive prompts during installation
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
    
    apt-get update >/dev/null 2>&1
    apt-get install -y iptables ipset iptables-persistent >/dev/null 2>&1
    echo -e "${GREEN}بسته‌های مورد نیاز با موفقیت نصب شدند.${NC}"
}

# Function to download the Iran IP list
download_iran_ips() {
    echo -e "${YELLOW}در حال دانلود لیست IP های ایران...${NC}"
    if curl -s -o "$WHITELIST_FILE" "$IRAN_IP_LIST_URL"; then
        echo -e "${GREEN}لیست IP های ایران با موفقیت در فایل $WHITELIST_FILE ذخیره شد.${NC}"
    else
        echo -e "${RED}خطا در دانلود لیست IP ها. لطفاً از اتصال اینترنت خود مطمئن شوید و یا فایل firewall.txt را به صورت دستی در مسیر $CONFIG_DIR قرار دهید.${NC}"
        exit 1
    fi
}

# Function to activate the firewall rules
activate_rules() {
    echo -e "${YELLOW}شروع فرآیند فعال‌سازی قوانین فایروال...${NC}"

    # --- NEW: Ask for SSH port ---
    read -p "لطفاً پورت SSH خود را وارد کنید (پیش‌فرض: 22): " user_ssh_port
    # Use user input if provided, otherwise default to 22
    local SSH_PORT=${user_ssh_port:-22}
    echo -e "${YELLOW}پورت SSH روی $SSH_PORT تنظیم شد.${NC}"
    # --- END NEW ---

    # 1. Install dependencies
    install_dependencies

    # 2. Create directory and backup
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "در حال ایجاد نسخه پشتیبان از قوانین فعلی فایروال..."
        iptables-save > "$BACKUP_FILE"
        echo -e "${GREEN}پشتیبان‌گیری در $BACKUP_FILE انجام شد.${NC}"
    fi

    # 3. Check for whitelist file
    if [ ! -f "$WHITELIST_FILE" ]; then
        echo -e "${YELLOW}فایل $WHITELIST_FILE یافت نشد.${NC}"
        read -p "آیا مایلید لیست IP های ایران به صورت خودکار دانلود شود؟ (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            download_iran_ips
        else
            echo -e "${RED}فعال‌سازی لغو شد. لطفاً فایل firewall.txt را در مسیر $CONFIG_DIR قرار دهید.${NC}"
            return
        fi
    fi

    # 4. Flush old rules and destroy old ipset
    echo "پاک کردن قوانین قدیمی..."
    iptables -F
    iptables -X
    ipset destroy "$IPSET_NAME" >/dev/null 2>&1

    # 5. Create new ipset and add IPs
    echo "ایجاد IPSet جدید و افزودن IP ها از فایل..."
    ipset create "$IPSET_NAME" hash:net
    while read -r line; do
        ipset add "$IPSET_NAME" "$line"
    done < "$WHITELIST_FILE"

    # 6. Apply new iptables rules
    echo "اعمال قوانین جدید فایروال..."
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    # Allow established and related connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    # Allow SSH
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    # Allow traffic from our whitelist
    iptables -A INPUT -m set --match-set "$IPSET_NAME" src -j ACCEPT
    # Set default policy to DROP
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT # Allow outgoing traffic

    # 7. Make rules persistent
    echo "ذخیره قوانین برای دائمی شدن پس از ریبوت..."
    iptables-save > /etc/iptables/rules.v4

    echo -e "${GREEN}✅ قوانین فایروال با موفقیت فعال و دائمی شدند.${NC}"
    echo -e "${YELLOW}دسترسی به سرور اکنون فقط برای IP های موجود در لیست سفید امکان‌پذیر است.${NC}"
}

# Function to deactivate firewall rules and restore from backup
deactivate_rules() {
    echo -e "${YELLOW}شروع فرآیند غیرفعال‌سازی قوانین...${NC}"
    if [ -f "$BACKUP_FILE" ]; then
        iptables-restore < "$BACKUP_FILE"
        iptables-save > /etc/iptables/rules.v4
        ipset destroy "$IPSET_NAME" >/dev/null 2>&1
        echo -e "${GREEN}✅ قوانین فایروال با موفقیت از نسخه پشتیبان بازیابی و دائمی شدند.${NC}"
    else
        echo -e "${RED}فایل پشتیبان ($BACKUP_FILE) یافت نشد. به صورت دستی قوانین را به حالت پیش‌فرض برمی‌گردانیم.${NC}"
        iptables -F
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables-save > /etc/iptables/rules.v4
        echo -e "${GREEN}✅ تمامی قوانین حذف شدند و پالیسی‌ها به ACCEPT تغییر یافتند.${NC}"
    fi
}

# Function to add a custom IP to the whitelist
add_ip() {
    read -p "لطفاً IP یا رنج CIDR مورد نظر برای افزودن را وارد کنید: " custom_ip
    if [[ -z "$custom_ip" ]]; then
        echo -e "${RED}ورودی نامعتبر است.${NC}"
        return
    fi

    # Add to running ipset
    if ipset add "$IPSET_NAME" "$custom_ip"; then
        # Add to the whitelist file for persistence
        echo "$custom_ip" >> "$WHITELIST_FILE"
        echo -e "${GREEN}✅ آی‌پی $custom_ip با موفقیت به لیست سفید اضافه شد.${NC}"
    else
        echo -e "${RED}خطا در افزودن IP. آیا قوانین فعال هستند و IP معتبر است؟${NC}"
    fi
}

# Function to remove a custom IP from the whitelist
remove_ip() {
    read -p "لطفاً IP یا رنج CIDR مورد نظر برای حذف را وارد کنید: " custom_ip
    if [[ -z "$custom_ip" ]]; then
        echo -e "${RED}ورودی نامعتبر است.${NC}"
        return
    fi

    # Remove from running ipset
    if ipset del "$IPSET_NAME" "$custom_ip"; then
        # Remove from the whitelist file
        sed -i "/^${custom_ip//\//\\/}$/d" "$WHITELIST_FILE"
        echo -e "${GREEN}✅ آی‌پی $custom_ip با موفقیت از لیست سفید حذف شد.${NC}"
    else
        echo -e "${RED}خطا در حذف IP. آیا IP در لیست وجود دارد؟${NC}"
    fi
}

# Function to completely uninstall and clean up
uninstall() {
    echo -e "${RED}!!! هشدار !!!${NC}"
    echo "این گزینه تمام قوانین فایروال را غیرفعال کرده، دایرکتوری کانفیگ ($CONFIG_DIR) را حذف می‌کند."
    read -p "آیا از حذف کامل اطمینان دارید؟ (y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        deactivate_rules
        rm -rf "$CONFIG_DIR"
        echo -e "${GREEN}اسکریپت و تنظیمات آن با موفقیت حذف شدند.${NC}"
        echo -e "${YELLOW}بسته‌های نصب شده (iptables, ipset) حذف نشدند. در صورت نیاز می‌توانید آنها را به صورت دستی حذف کنید.${NC}"
    else
        echo "عملیات حذف لغو شد."
    fi
}

# Function to display the menu
show_menu() {
    echo ""
    echo "==================================="
    echo "   مدیریت فایروال دسترسی ایران    "
    echo "==================================="
    echo "1. فعال‌سازی قوانین (ایران اکسس)"
    echo "2. غیرفعال‌سازی قوانین (بازیابی پشتیبان)"
    echo "3. افزودن یک IP خاص به لیست سفید"
    echo "4. حذف یک IP خاص از لیست سفید"
    echo "5. حذف کامل اسکریپت و تنظیمات"
    echo "6. خروج"
    echo "-----------------------------------"
}

# --- Main Logic ---
check_root

while true; do
    show_menu
    read -p "لطفاً گزینه مورد نظر را انتخاب کنید [1-6]: " choice

    case $choice in
        1)
            activate_rules
            ;;
        2)
            deactivate_rules
            ;;
        3)
            add_ip
            ;;
        4)
            remove_ip
            ;;
        5)
            uninstall
            ;;
        6)
            echo "خروج از برنامه."
            exit 0
            ;;
        *)
            echo -e "${RED}گزینه نامعتبر است. لطفاً عددی بین 1 تا 6 وارد کنید.${NC}"
            ;;
    esac
done
