#!/bin/bash

#================================================================
# Firewall Manager Script for Ubuntu (v2 - Revised)
# Author: Gemini
# Description: Manages iptables rules to restrict access based on an IP whitelist.
#================================================================

# --- Internal Variables ---
CONFIG_DIR="/etc/firewall_manager"
BACKUP_FILE="$CONFIG_DIR/iptables-backup.rules"
WHITELIST_FILE="$CONFIG_DIR/firewall.txt"
IPSET_NAME="whitelist_set"
# --- URL points to your GitHub repository ---
IP_LIST_URL="https://raw.githubusercontent.com/Argo160/IranAccess/main/firewall.txt"

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Functions ---

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}خطا: این اسکریپت باید با دسترسی root اجرا شود. (sudo ./firewall_manager.sh)${NC}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${YELLOW}بررسی و نصب بسته‌های مورد نیاز (iptables, ipset, iptables-persistent)...${NC}"
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
    apt-get update >/dev/null 2>&1
    apt-get install -y iptables ipset iptables-persistent >/dev/null 2>&1
    echo -e "${GREEN}بسته‌های مورد نیاز با موفقیت نصب شدند.${NC}"
}

download_ip_list() {
    echo -e "${YELLOW}در حال دانلود لیست IP از گیت‌هاب شما...${NC}"
    if curl -s -o "$WHITELIST_FILE" "$IP_LIST_URL"; then
        echo -e "${GREEN}لیست IP با موفقیت در فایل $WHITELIST_FILE ذخیره شد.${NC}"
    else
        echo -e "${RED}خطا در دانلود لیست IP ها. لطفاً از درستی آدرس گیت‌هاب و اتصال اینترنت خود مطمئن شوید.${NC}"
        exit 1
    fi
}

activate_rules() {
    echo -e "${YELLOW}شروع فرآیند فعال‌سازی قوانین فایروال...${NC}"

    read -p "لطفاً پورت SSH خود را وارد کنید (پیش‌فرض: 22): " user_ssh_port
    local SSH_PORT=${user_ssh_port:-22}
    echo -e "${YELLOW}پورت SSH روی $SSH_PORT تنظیم شد.${NC}"

    install_dependencies
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "در حال ایجاد نسخه پشتیبان از قوانین فعلی فایروال..."
        iptables-save > "$BACKUP_FILE"
        echo -e "${GREEN}پشتیبان‌گیری در $BACKUP_FILE انجام شد.${NC}"
    fi

    if [ ! -f "$WHITELIST_FILE" ]; then
        echo -e "${YELLOW}فایل $WHITELIST_FILE یافت نشد.${NC}"
        read -p "آیا مایلید لیست IP ها از گیت‌هاب شما دانلود شود؟ (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            download_ip_list
        else
            echo -e "${RED}فعال‌سازی لغو شد.${NC}"
            return
        fi
    fi

    echo "پاک کردن قوانین قدیمی..."
    iptables -F
    iptables -X
    ipset destroy "$IPSET_NAME" >/dev/null 2>&1

    echo "ایجاد IPSet جدید و افزودن IP ها از فایل..."
    ipset create "$IPSET_NAME" hash:net
    while read -r line; do
        if [[ ! "$line" =~ ^# && -n "$line" ]]; then
            ipset add "$IPSET_NAME" "$line"
        fi
    done < "$WHITELIST_FILE"

    echo "اعمال قوانین جدید فایروال..."
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    iptables -A INPUT -m set --match-set "$IPSET_NAME" src -j ACCEPT
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    echo "ذخیره قوانین برای دائمی شدن پس از ریبوت..."
    iptables-save > /etc/iptables/rules.v4

    echo -e "${GREEN}✅ قوانین فایروال با موفقیت فعال و دائمی شدند.${NC}"
}

# --- REVISED AND IMPROVED FUNCTION ---
deactivate_rules() {
    echo -e "${YELLOW}شروع فرآیند غیرفعال‌سازی و بازگردانی فایروال...${NC}"

    echo "1. پاک کردن تمام قوانین فعلی و تنظیم پالیسی پیش‌فرض به ACCEPT..."
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    echo "2. حذف ipset..."
    ipset destroy "$IPSET_NAME" >/dev/null 2>&1

    if [ -f "$BACKUP_FILE" ]; then
        echo "3. بازیابی قوانین از فایل پشتیبان..."
        iptables-restore < "$BACKUP_FILE"
        echo -e "${GREEN}قوانین با موفقیت از نسخه پشتیبان بازیابی شدند.${NC}"
    else
        echo -e "${YELLOW}3. فایل پشتیبان یافت نشد. فایروال در حالت باز (ACCEPT) باقی می‌ماند.${NC}"
    fi

    echo "4. ذخیره کردن وضعیت فعلی برای دائمی شدن..."
    iptables-save > /etc/iptables/rules.v4

    echo -e "${GREEN}✅ فرآیند غیرفعال‌سازی تکمیل شد.${NC}"
}

# --- REVISED AND IMPROVED FUNCTION ---
add_ip() {
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        echo -e "${RED}خطا: به نظر می‌رسد قوانین فایروال (و ipset) فعال نیستند. ابتدا گزینه 1 را اجرا کنید.${NC}"
        return
    fi

    read -p "لطفاً IP یا رنج CIDR مورد نظر برای افزودن را وارد کنید: " custom_ip
    if [[ -z "$custom_ip" ]]; then
        echo -e "${RED}ورودی نامعتبر است.${NC}"
        return
    fi

    ipset add "$IPSET_NAME" "$custom_ip"
    
    if ipset test "$IPSET_NAME" "$custom_ip" >/dev/null 2>&1; then
        echo "$custom_ip" >> "$WHITELIST_FILE"
        echo -e "${GREEN}✅ آی‌پی $custom_ip با موفقیت به لیست سفید در حال اجرا اضافه شد و در فایل ذخیره گردید.${NC}"
    else
        echo -e "${RED}خطا در افزودن IP به ipset. لطفاً از فرمت صحیح IP/CIDR مطمئن شوید.${NC}"
    fi
}

# --- REVISED AND IMPROVED FUNCTION ---
remove_ip() {
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        echo -e "${RED}خطا: به نظر می‌رسد قوانین فایروال (و ipset) فعال نیستند.${NC}"
        return
    fi

    read -p "لطفاً IP یا رنج CIDR مورد نظر برای حذف را وارد کنید: " custom_ip
    if [[ -z "$custom_ip" ]]; then
        echo -e "${RED}ورودی نامعتبر است.${NC}"
        return
    fi

    if ! ipset test "$IPSET_NAME" "$custom_ip" >/dev/null 2>&1; then
        echo -e "${YELLOW}هشدار: آی‌پی $custom_ip از قبل در لیست سفید وجود ندارد.${NC}"
        # Attempt to remove from file just in case they are out of sync
        sed -i.bak "/^${custom_ip//\//\\/}$/d" "$WHITELIST_FILE"
        return
    fi

    ipset del "$IPSET_NAME" "$custom_ip"

    if ! ipset test "$IPSET_NAME" "$custom_ip" >/dev/null 2>&1; then
        sed -i "/^${custom_ip//\//\\/}$/d" "$WHITELIST_FILE"
        echo -e "${GREEN}✅ آی‌پی $custom_ip با موفقیت از لیست سفید در حال اجرا و از فایل حذف شد.${NC}"
    else
        echo -e "${RED}خطا در حذف IP از ipset در حال اجرا.${NC}"
    fi
}

uninstall() {
    echo -e "${RED}!!! هشدار !!!${NC}"
    echo "این گزینه تمام قوانین فایروال را غیرفعال کرده، دایرکتوری کانفیگ ($CONFIG_DIR) را حذف می‌کند."
    read -p "آیا از حذف کامل اطمینان دارید؟ (y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        deactivate_rules
        rm -rf "$CONFIG_DIR"
        echo -e "${GREEN}اسکریپت و تنظیمات آن با موفقیت حذف شدند.${NC}"
    else
        echo "عملیات حذف لغو شد."
    fi
}

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
        1) activate_rules ;;
        2) deactivate_rules ;;
        3) add_ip ;;
        4) remove_ip ;;
        5) uninstall ;;
        6) echo "خروج از برنامه."; exit 0 ;;
        *) echo -e "${RED}گزینه نامعتبر است. لطفاً عددی بین 1 تا 6 وارد کنید.${NC}" ;;
    esac
done
