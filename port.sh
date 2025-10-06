#!/bin/bash
# iptables 端口转发配置脚本
# 支持 TCP/UDP 转发，可选择临时生效或永久保存

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请以 root 权限运行此脚本（使用 sudo）" >&2
    exit 1
fi

# 显示菜单
echo "===== iptables 端口转发配置工具 ====="
echo "1. 设置端口转发"
echo "2. 清除所有转发规则"
echo "3. 查看当前转发规则"
echo "4. 保存规则（永久生效）"
echo "5. 退出"
read -p "请选择操作 [1-5]: " choice

# 开启 IP 转发功能
enable_ip_forward() {
    # 临时开启
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # 永久开启（重启后生效）
    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi
    sysctl -p > /dev/null
    echo "已开启 IP 转发功能"
}

# 设置端口转发
setup_forward() {
    enable_ip_forward
    
    read -p "请输入转发协议（tcp/udp，默认 tcp）: " proto
    proto=${proto:-tcp}  # 默认使用 tcp
    
    read -p "请输入中转服务器监听端口: " local_port
    
    read -p "请输入目标服务器 IP 地址: " dest_ip
    
    read -p "请输入目标服务器端口: " dest_port
    
    # 获取中转服务器的公网 IP（取第一个非本地 IP）
    local_ip=$(hostname -I | awk '{print $1}')
    read -p "检测到中转服务器 IP 为 $local_ip，是否使用此 IP？(y/n): " use_local
    if [ "$use_local" != "y" ] && [ "$use_local" != "Y" ]; then
        read -p "请输入中转服务器 IP 地址: " local_ip
    fi

    # 添加转发规则
    echo "正在添加 $proto 转发规则：$local_ip:$local_port -> $dest_ip:$dest_port"
    
    # PREROUTING 链：将外部访问转发到目标服务器
    iptables -t nat -A PREROUTING -p $proto --dport $local_port -j DNAT --to-destination $dest_ip:$dest_port
    
    # POSTROUTING 链：源地址转换（让目标服务器知道返回给谁）
    iptables -t nat -A POSTROUTING -p $proto -d $dest_ip --dport $dest_port -j SNAT --to-source $local_ip
    
    echo "转发规则添加成功（临时生效，重启后会丢失）"
    read -p "是否立即保存规则？(y/n): " save_now
    if [ "$save_now" = "y" ] || [ "$save_now" = "Y" ]; then
        save_rules
    fi
}

# 清除所有转发规则
clear_rules() {
    echo "正在清除所有转发规则..."
    # 清除 nat 表中的转发规则
    iptables -t nat -F PREROUTING
    iptables -t nat -F POSTROUTING
    echo "转发规则已清除（临时生效）"
    read -p "是否保存清除后的状态？(y/n): " save_now
    if [ "$save_now" = "y" ] || [ "$save_now" = "Y" ]; then
        save_rules
    fi
}

# 查看当前转发规则
show_rules() {
    echo "===== 当前 nat 表转发规则 ====="
    iptables -t nat -L PREROUTING --line-numbers
    echo "----------------------------------"
    iptables -t nat -L POSTROUTING --line-numbers
}

# 保存规则（永久生效）
save_rules() {
    echo "正在保存规则..."
    # 不同发行版保存方式不同
    if [ -f /etc/redhat-release ]; then
        # CentOS/RHEL 系统
        service iptables save > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            iptables-save > /etc/sysconfig/iptables
        fi
    elif [ -f /etc/debian_version ]; then
        # Ubuntu/Debian 系统
        if ! command -v iptables-save &> /dev/null; then
            echo "检测到 Debian/Ubuntu 系统，正在安装 iptables-persistent..."
            apt-get update > /dev/null
            apt-get install -y iptables-persistent > /dev/null
        fi
        netfilter-persistent save > /dev/null
    else
        # 通用方式
        iptables-save > /etc/iptables.rules
        echo "规则已保存到 /etc/iptables.rules"
        echo "请手动配置开机加载（如在 /etc/rc.local 中添加 iptables-restore < /etc/iptables.rules）"
    fi
    echo "规则保存成功，重启后仍有效"
}

# 根据用户选择执行操作
case $choice in
    1)
        setup_forward
        ;;
    2)
        clear_rules
        ;;
    3)
        show_rules
        ;;
    4)
        save_rules
        ;;
    5)
        echo "退出脚本"
        exit 0
        ;;
    *)
        echo "无效选择，请输入 1-5 之间的数字"
        exit 1
        ;;
esac
