#!/bin/bash
# =========================================================
# e-BestTrace - Linux VPS 回程路由一键测试 (增强交互版)
# 融合 eTraffic 5.5 UI 布局，新增 ICMP/TCP 协议切换
# =========================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ================== 颜色代码与风格统一 ==================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'

# ================== 全局状态变量 ==================
TRACE_PROTO="ICMP"
PROTO_FLAG="-I"

# 初始化汇总分类数组 (每次运行测试前需清空)
init_arrays() {
    ROWS_CT=()
    ROWS_CU=()
    ROWS_CM=()
    ROWS_EDU=()
    ROWS_OTHER=()
}

# ================== 数据源配置 ==================
ip_list=("219.141.147.210" "202.106.50.1" "221.179.155.161" \
         "202.96.209.133" "210.22.97.1" "211.136.112.200" \
         "202.96.128.86"   "210.21.196.6" "120.196.165.24" \
         "118.112.11.12" "119.6.6.6" "211.137.96.205" \
         "202.112.14.151")

ip_addr=("北京电信" "北京联通" "北京移动" \
         "上海电信" "上海联通" "上海移动" \
         "广州电信" "广州联通" "广州移动" \
         "成都电信" "成都联通" "成都移动" \
         "成都教育网")

isp_codes=("CT" "CU" "CM" "CT" "CU" "CM" "CT" "CU" "CM" "CT" "CU" "CM" "EDU")

# ================== 交互辅助函数 ==================
pause_and_return() { 
    echo ""
    read -n 1 -s -r -p ">>> 测试完成，按任意键返回主菜单..."
}

print_sep() {
    echo -e "${CYAN}----------------------------------------------------------------------${RESET}"
}

check_env() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：本脚本需要 Root 权限才能正常运行！${RESET}"
        exit 1
    fi

    if [ ! -f "/usr/local/bin/nexttrace" ]; then
        echo -e "${YELLOW}--> 正在安装核心组件 NextTrace...${RESET}"
        curl nxtrace.org/nt | bash >/dev/null 2>&1
    fi
}

# ================== 核心分析逻辑 ==================
analyze_route() {
    local log_content=$1
    local isp_type=$2
    local target_name=$3
    local target_ip=$4
    
    local clean_content=$(echo "$log_content" | sed 's/\x1b\[[0-9;]*m//g')
    
    # --- 特征提取 ---
    local has_as4809=$(echo "$clean_content" | grep -E "AS4809|59\.43\.")
    local has_as9929=$(echo "$clean_content" | grep -E "AS9929|99\.29\.|AS10099")
    local has_as4837=$(echo "$clean_content" | grep -E "AS4837|219\.158\.")
    local has_cmin2=$(echo "$clean_content" | grep -E "AS58807") 
    local has_cmi=$(echo "$clean_content" | grep -E "AS58453|AS9808|223\.120\.")
    local domestic_segment=$(echo "$clean_content" | grep -iE "China|CN|Beijing|Shanghai|Guangzhou|Shenzhen|Chengdu|Anhui|Sichuan|Guangdong")
    local domestic_has_4809=$(echo "$domestic_segment" | grep -E "AS4809|59\.43\.")

    local ret_color_type=""

    echo -e "${YELLOW}>>> [智能分析] 线路判定 (目标: $isp_type, 协议: $TRACE_PROTO)：${RESET}"

    if [ -n "$domestic_has_4809" ]; then
        echo -e "   类型：${GREEN}${BOLD}电信 CN2 GIA (AS4809)${RESET}"
        echo -e "   详情：检测到回程国内段走 AS4809，顶级线路。"
        ret_color_type="${GREEN}CN2 GIA${RESET}"
    elif [ -n "$has_as9929" ]; then
        echo -e "   类型：${GREEN}${BOLD}联通 9929 (CU Premium)${RESET}"
        echo -e "   详情：检测到 AS9929 (联通A网) 骨干。"
        ret_color_type="${GREEN}联通 9929${RESET}"
    elif [ -n "$has_cmin2" ]; then
        echo -e "   类型：${GREEN}${BOLD}移动 CMIN2 (AS58807)${RESET}"
        echo -e "   详情：检测到移动高端精品网 AS58807。"
        ret_color_type="${GREEN}移动 CMIN2${RESET}"
    elif [ -n "$has_as4809" ]; then
        echo -e "   类型：${YELLOW}${BOLD}电信 CN2 GT (Global Transit)${RESET}"
        echo -e "   详情：仅国际段走 AS4809，回国切入 163 骨干。"
        ret_color_type="${YELLOW}CN2 GT${RESET}"
    elif [ -n "$has_as4837" ]; then
        echo -e "   类型：${CYAN}联通 4837 (169 Backbone)${RESET}"
        echo -e "   详情：联通民用骨干网。"
        ret_color_type="${CYAN}联通 4837${RESET}"
    elif [ -n "$has_cmi" ]; then
        echo -e "   类型：${CYAN}移动 CMI (AS58453/9808)${RESET}"
        echo -e "   详情：走移动国际线路 (CMI)。"
        ret_color_type="${CYAN}移动 CMI${RESET}"
    else
        case $isp_type in
            "CT") echo -e "   类型：${RED}电信 163 骨干网 (AS4134)${RESET}"; ret_color_type="${RED}163 骨干${RESET}" ;;
            "CU") echo -e "   类型：${RED}联通普通线路${RESET}"; ret_color_type="${RED}联通普通${RESET}" ;;
            "CM") echo -e "   类型：${MAGENTA}移动普通线路${RESET}"; ret_color_type="${MAGENTA}移动普通${RESET}" ;;
            "EDU") echo -e "   类型：${CYAN}教育网 (CERNET)${RESET}"; ret_color_type="${CYAN}教育网${RESET}" ;;
            *) echo -e "   类型：其他/混合网络"; ret_color_type="其他网络" ;;
        esac
    fi

    # === 构建汇总行 ===
    local name_len=${#target_name}
    local pad_spaces=""
    if [[ $name_len -eq 4 ]]; then pad_spaces="        "; fi
    if [[ $name_len -eq 5 ]]; then pad_spaces="      "; fi
    if [[ $name_len -eq 3 ]]; then pad_spaces="          "; fi
    if [[ $name_len -eq 6 ]]; then pad_spaces="    "; fi
    if [[ -z "$pad_spaces" ]]; then pad_spaces="    "; fi

    local summary_line=$(printf "%s%s %-18s %-20b" "$target_name" "$pad_spaces" "$target_ip" "$ret_color_type")

    if [[ "$isp_type" == "CT" ]]; then ROWS_CT+=("$summary_line"); fi
    if [[ "$isp_type" == "CU" ]]; then ROWS_CU+=("$summary_line"); fi
    if [[ "$isp_type" == "CM" ]]; then ROWS_CM+=("$summary_line"); fi
    if [[ "$isp_type" == "EDU" ]]; then ROWS_EDU+=("$summary_line"); fi
    if [[ "$isp_type" == "OTHER" ]]; then ROWS_OTHER+=("$summary_line"); fi
}

detect_isp_type() {
    local log_content=$1
    local lower_content=$(echo "$log_content" | tr '[:upper:]' '[:lower:]')
    if echo "$lower_content" | grep -qE "telecom|dx|as4134|as4809"; then echo "CT"
    elif echo "$lower_content" | grep -qE "unicom|lt|as4837|as9929"; then echo "CU"
    elif echo "$lower_content" | grep -qE "mobile|yd|as9808|cmi"; then echo "CM"
    elif echo "$lower_content" | grep -qE "education|cernet|edu"; then echo "EDU"
    else echo "OTHER"; fi
}

# ================== 打印汇总表 ==================
print_final_summary() {
    echo ""
    echo -e "${MAGENTA}=============================================================${RESET}"
    echo -e "${CYAN}               回程路由测试汇总 (${TRACE_PROTO} 协议)               ${RESET}"
    echo -e "${MAGENTA}=============================================================${RESET}"
    echo -e "节点名称         IP 地址            线路类型"
    echo "-------------------------------------------------------------"
    
    for line in "${ROWS_CT[@]}"; do echo -e "$line"; done
    for line in "${ROWS_CU[@]}"; do echo -e "$line"; done
    for line in "${ROWS_CM[@]}"; do echo -e "$line"; done
    for line in "${ROWS_EDU[@]}"; do echo -e "$line"; done
    for line in "${ROWS_OTHER[@]}"; do echo -e "$line"; done

    echo "-------------------------------------------------------------"
    echo -e "${YELLOW}* 图例: ${GREEN}绿色=高端(GIA/9929/CMIN2)${RESET} | ${CYAN}蓝色=主流(4837/CMI)${RESET} | ${RED}红色=普通${RESET}"
    echo -e "${YELLOW}* 提示: 线路判断结果仅供参考，路由表现受多重因素影响${RESET}"
}

# ================== 执行测试逻辑 ==================
run_tests() {
    local test_mode=$1
    local mode_name=$2
    init_arrays
    clear
    
    echo -e "${CYAN}================== 开始测试 (模式: $mode_name) ==================${RESET}"
    echo -e "${BLUE}>> 正在使用协议:${RESET} ${YELLOW}${TRACE_PROTO}${RESET}"
    print_sep

    local count=0
    local len=${#ip_list[@]}

    for ((i=0; i<len; i++)); do
        target_ip=${ip_list[$i]}
        target_name=${ip_addr[$i]}
        isp_type=${isp_codes[$i]}
        
        local should_run=false
        case $test_mode in
            "ALL") should_run=true ;;
            "CT") [[ "$isp_type" == "CT" ]] && should_run=true ;;
            "CU") [[ "$isp_type" == "CU" ]] && should_run=true ;;
            "CM") [[ "$isp_type" == "CM" ]] && should_run=true ;;
            "EDU") [[ "$isp_type" == "EDU" ]] && should_run=true ;;
        esac
        
        if $should_run; then
            ((count++))
            echo -e "正在测试: ${GREEN}${target_name}${RESET} [${target_ip}]"
            nexttrace $PROTO_FLAG "$target_ip" -q 1 -M | tee /tmp/nt_temp.log
            analyze_route "$(cat /tmp/nt_temp.log)" "$isp_type" "$target_name" "$target_ip"
            print_sep
            sleep 1
        fi
    done

    rm -f /tmp/nt_temp.log
    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}提示：该模式下没有匹配的测试节点。${RESET}"
    else
        print_final_summary
    fi
}

run_custom_test() {
    init_arrays
    echo ""
    read -p "请输入目标 IP: " custom_ip
    echo -e "\n${CYAN}================ 正在测试: ${GREEN}自定义测速点${CYAN} [${custom_ip}] ================${RESET}"
    echo -e "${BLUE}>> 正在使用协议:${RESET} ${YELLOW}${TRACE_PROTO}${RESET}\n"
    
    nexttrace $PROTO_FLAG "$custom_ip" -q 1 -M | tee /tmp/nt_temp.log
    raw_log=$(cat /tmp/nt_temp.log)
    detected_isp=$(detect_isp_type "$raw_log")
    analyze_route "$raw_log" "$detected_isp" "自定义测速点" "$custom_ip"
    rm -f /tmp/nt_temp.log
    print_final_summary
}

toggle_protocol() {
    if [[ "$TRACE_PROTO" == "ICMP" ]]; then
        TRACE_PROTO="TCP"
        PROTO_FLAG="-T"
        echo -e "\n${GREEN}>> 测试协议已切换为: TCP${RESET}"
    else
        TRACE_PROTO="ICMP"
        PROTO_FLAG="-I"
        echo -e "\n${GREEN}>> 测试协议已切换为: ICMP${RESET}"
    fi
    sleep 1.5
}

# ================== 初始化 ==================
check_env
SYS_OS=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"' || echo "Unknown Linux")

# ================== 主菜单界面 ==================
while true; do
    clear
    echo -e "${MAGENTA}=========================================================${RESET}"
    echo -e "${CYAN}         e-BestTrace - Linux VPS 回程路由一键测试        ${RESET}"
    echo -e "${MAGENTA}=========================================================${RESET}"
    echo -e " ${BLUE}系统环境 :${RESET} ${WHITE}${SYS_OS}${RESET}"
    echo -e " ${BLUE}当前协议 :${RESET} ${GREEN}${BOLD}${TRACE_PROTO}${RESET} ${YELLOW}(选1进行切换)${RESET}"
    echo -e "${MAGENTA}---------------------------------------------------------${RESET}"
    echo -e "  ${YELLOW}1.${RESET} 切换测试协议 (ICMP / TCP)"
    echo -e "  ${YELLOW}2.${RESET} 测试所有节点 (默认)"
    echo -e "  ${YELLOW}3.${RESET} 仅测试 电信 (China Telecom)"
    echo -e "  ${YELLOW}4.${RESET} 仅测试 联通 (China Unicom)"
    echo -e "  ${YELLOW}5.${RESET} 仅测试 移动 (China Mobile)"
    echo -e "  ${YELLOW}6.${RESET} 仅测试 教育网 (Education)"
    echo -e "  ${YELLOW}7.${RESET} 自定义 IP 测试 (自动识别运营商)"
    echo -e "  ${WHITE}0.${RESET} 退出脚本"
    echo -e "${MAGENTA}=========================================================${RESET}"
    read -p "  请输入选项 [0-7]: " choice

    case "$choice" in
        1) toggle_protocol ;;
        2|"") run_tests "ALL" "所有节点"; pause_and_return ;;
        3) run_tests "CT" "仅电信"; pause_and_return ;;
        4) run_tests "CU" "仅联通"; pause_and_return ;;
        5) run_tests "CM" "仅移动"; pause_and_return ;;
        6) run_tests "EDU" "仅教育网"; pause_and_return ;;
        7) run_custom_test; pause_and_return ;;
        0) clear; echo -e "${GREEN}Bye${RESET}"; exit 0 ;;
        *) echo -e "${RED}输入无效，请重新输入！${RESET}"; sleep 1 ;;
    esac
done
