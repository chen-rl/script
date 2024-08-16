#!/bin/bash

# 作者: chenrl
# 创建日期: 2024-07-12
# 修改日期：2024-08-16
# 版本: 1.0.3
# 版本变更：
#       1.scp修改为rsync
#       2.ssh增加持久化
#       3.增加镜像更新
# 描述: 此脚本管理各种组件（stream、agent、manage-shell、screen、input）的构建和部署，
#       用于指定的分支或远程IP地址。现在支持从文件读取IP并多线程批量更新设备上的程序。

# 定义常量
readonly LOCAL_DIRECTORY_BASE="/data/build-test"
readonly FILEPATH_ARM_STREAM="${LOCAL_DIRECTORY_BASE}/arm-stream"
readonly FILEPATH_ARM_AGENT="${LOCAL_DIRECTORY_BASE}/arm-agent"
readonly FILEPATH_MANAGE_SHELL="${LOCAL_DIRECTORY_BASE}/manage-shell"
readonly FILEPATH_CAPTURE_SCREEN="${LOCAL_DIRECTORY_BASE}/capture-screen"
readonly FILEPATH_INPUT_DEVICE_SERVICE="${LOCAL_DIRECTORY_BASE}/input-device-service"
readonly LOG_DIRECTORY="${LOCAL_DIRECTORY_BASE}/sh/build_update_logs"
readonly LOG_FILE="${LOG_DIRECTORY}/$(date '+%Y-%m-%d').log"

# 创建日志目录
mkdir -p "${LOG_DIRECTORY}"

# 日志记录函数
log_info() {
    echo -e "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "${LOG_FILE}" >&2
}

# 显示帮助信息
show_help() {
    echo "用法: $0 <命令> <子命令> <分支或IP或IP文件>"
    echo
    echo "命令:"
    echo "  stream    arm-stream程序"
    echo "  agent     arm-agent程序"
    echo "  manage    manage-shell脚本"
    echo "  screen    arm-screen程序"
    echo "  input     input-device服务"
    echo "  img       镜像更新"
    echo "  all       更新远程设备上的所有程序"
    echo
    echo "子命令:"
    echo "  m <分支>         更新git分支并打包编译"
    echo "  u <ip或IP文件>   更新远程设备上的程序"
    echo "  img <ip或IP文件> <镜像文件>   更新远程设备上的镜像"
    echo
    echo "示例:"
    echo "  $0 stream m master          从master分支更新并生成arm-stream程序"
    echo "  $0 agent u 192.168.1.100    更新远程设备IP为192.168.1.100上的agent程序"
    echo "  $0 img u 192.168.1.100 /path/to/local_image.tgz   更新远程设备IP为192.168.1.100上的镜像"
    echo "  $0 all u ip_list.txt        从ip_list.txt文件中读取IP并更新所有设备上的程序"
    echo
    exit 1
}

# 获取匹配的最新文件
get_latest_file() {
    local directory=$1
    local pattern=$2
    ls -t ${directory}/${pattern} 2>/dev/null | head -1
}

# 初始化文件路径
FILE_STREAM=$(get_latest_file "${FILEPATH_ARM_STREAM}/build" "arm-stream*")
FILE_MEDIA=$(get_latest_file "${FILEPATH_ARM_STREAM}/media_server/lib" "libmedia_server.so.1.*")
FILE_AGENT=$(get_latest_file "${FILEPATH_ARM_AGENT}/bin" "*")
FILE_SCREEN=$(get_latest_file "${FILEPATH_CAPTURE_SCREEN}/bin" "arm-screen*")
FILE_INPUT=$(get_latest_file "${FILEPATH_INPUT_DEVICE_SERVICE}/bin" "input-dev-server*")

# 编译打包
make_package() {
    local directory=$1
    cd "${directory}/build" || exit
    cmake ..
    make -j 
    log_info "$(basename "${directory}") 包编译成功"
}

# 更新远程设备上的程序
update_program() {
    local ip=$1
    local remote_path=$2
    local local_file=$3
    local link_name=$4
    local stop_command=$5
    local start_command=$6
    if [ -n "${stop_command}" ]; then
        sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 root@"${ip}" "${stop_command}" | tee -a "${LOG_FILE}"
    fi
    rsync -avz -e "sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600" "${local_file}" "root@${ip}:${remote_path}" | tee -a "${LOG_FILE}"
    #sshpass -p 'root' scp -rf "${local_file}" root@"${ip}:${remote_path}"
    if [ "${link_name}" == "libmedia_server.so" ]; then
        sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 root@"${ip}"  "ln -snf ${remote_path}libmedia_server.so.1 ${remote_path}${link_name} ; ln -snf ${remote_path}$(basename ${local_file}) ${remote_path}libmedia_server.so.1" | tee -a "${LOG_FILE}"
    elif [ "${link_name}" != "manage-shell" ]; then
    	sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 root@"${ip}"  "ln -snf ${remote_path}$(basename ${local_file}) ${remote_path}${link_name}" | tee -a "${LOG_FILE}"
    fi
    if [ -n "${start_command}" ]; then
        sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 root@"${ip}" "${start_command}" | tee -a "${LOG_FILE}"
    fi
    log_info "已更新 $(basename "${local_file}") 到 ${ip}"
}

# 更新git分支并编译打包
update_git_branch() {
    local directory=$1
    local branch=$2
    local package_function=$3

    cd "${directory}" || exit
    git checkout . | tee -a "${LOG_FILE}" 
    if git show-ref --verify --quiet "refs/heads/${branch}"; then
        git checkout "${branch}" | tee -a "${LOG_FILE}"
        git pull
    else
        if git ls-remote --exit-code origin "${branch}" >/dev/null 2>&1; then
            git fetch origin | tee -a "${LOG_FILE}"
            git checkout -b "${branch}" "origin/${branch}" | tee -a "${LOG_FILE}"
        else
            log_error "无效的分支名称。请检查分支名称并重试。"
            exit 1
        fi
    fi
    ${package_function}
}

# 从文件读取IP并多线程更新程序
update_from_file_parallel() {
    local file=$1
    local remote_path=$2
    local local_file=$3
    local link_name=$4
    local stop_command=$5
    local start_command=$6

    while IFS= read -r ip; do
        if [ -n "${ip}" ]; then
            (
                update_program "${ip}" "${remote_path}" "${local_file}" "${link_name}" "${stop_command}" "${start_command}"
            ) &
        fi
    done < "${file}"
    wait
}

# 更新镜像
update_image() {
    local ip=$1
    local local_image_file=$2

    # 停止 agent，停止容器，删除容器，删除已挂载镜像，删除目标 IP目录下的镜像文件
    sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 root@"${ip}" "systemctl stop arm-agent ; docker stop \$(docker ps -aq) ; docker rm \$(docker ps -aq) ; docker rmi \$(docker images -aq) ; rm /data/rk3588_docker-android10-user-super.img*"

    # 将镜像移动到目标物理机
    sshpass -p 'root' scp -r "${local_image_file}" root@"${ip}:/data/"

    # 镜像名获取
    local filename=$(sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 root@"${ip}" 'ls -t /data/*.tgz | head -1')

    # 使用 manage-shell 脚本创建镜像
    sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 root@"${ip}" "/userdata/arm-agent/bin/manage-shell/android_ctl.sh createImage ${filename}"

    # 将最新创建的镜像名更新到 conf/manage-shell/android_common.conf 中
    sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 root@"${ip}" "sed -i 's/.*image=.*//' /userdata/arm-agent/conf/manage-shell/android_common.conf"

    # 启动 agent
    sshpass -p 'root' ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 root@"${ip}" "systemctl start arm-agent"

    log_info "镜像更新完成: ${local_image_file} 到 ${ip}"
}

# 批量更新镜像
update_images_batch() {
    local file=$1
    local local_image_file=$2

    while IFS= read -r ip; do
        if [ -n "${ip}" ]; then
            (
                update_image "${ip}" "${local_image_file}"
            ) &
        fi
    done < "${file}"
    wait
}

# 检查输入参数
if [ "$#" -lt 3 ]; then
    show_help
fi

log_info "脚本开始执行，命令: $0 $*"

case "$1" in
    stream)
        case "$2" in
            m)
                update_git_branch "${FILEPATH_ARM_STREAM}" "$3" "make_package ${FILEPATH_ARM_STREAM}/media_server"
                update_git_branch "${FILEPATH_ARM_STREAM}" "$3" "make_package ${FILEPATH_ARM_STREAM}"
                ;;
            u)
                if [ -f "$3" ]; then
                    update_from_file_parallel "$3" "/userdata/arm-agent/libs/" "${FILE_MEDIA}" "libmedia_server.so" "" ""
                    update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILE_STREAM}" "arm-stream" "pkill arm-stream" ""
                else
                    update_program "$3" "/userdata/arm-agent/libs/" "${FILE_MEDIA}" "libmedia_server.so" "" ""
                    update_program "$3" "/userdata/arm-agent/bin/" "${FILE_STREAM}" "arm-stream" "pkill arm-stream" ""
                fi
                ;;
            *)
                show_help
                ;;
        esac
        ;;
    agent)
        case "$2" in
            m)
                update_git_branch "${FILEPATH_ARM_AGENT}" "$3" "make_package ${FILEPATH_ARM_AGENT}"
                ;;
            u)
                if [ -f "$3" ]; then
                    update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILE_AGENT}" "arm-agent" "systemctl stop arm-agent" "systemctl start arm-agent"
                else
                    update_program "$3" "/userdata/arm-agent/bin/" "${FILE_AGENT}" "arm-agent" "systemctl stop arm-agent" "systemctl start arm-agent"
                fi
                ;;
            *)
                show_help
                ;;
        esac
        ;;
    manage)
        case "$2" in
            m)
                update_git_branch "${FILEPATH_MANAGE_SHELL}" "$3" ""
                ;;
            u)
                if [ -f "$3" ]; then
			        update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILEPATH_MANAGE_SHELL}" "manage-shell" "systemctl stop arm-agent; docker stop \$(docker ps -aq); docker rm \$(docker ps -aq)" "systemctl start arm-agent"
                else
			        update_program "$3" "/userdata/arm-agent/bin/" "${FILEPATH_MANAGE_SHELL}" "manage-shell" "systemctl stop arm-agent;docker stop \$(docker ps -aq); docker rm \$(docker ps -aq)" "systemctl start arm-agent"
                fi
                ;;
            *)
                show_help
                ;;
        esac
        ;;
    screen)
        case "$2" in
            m)
                update_git_branch "${FILEPATH_CAPTURE_SCREEN}" "$3" "make_package ${FILEPATH_CAPTURE_SCREEN}"
                ;;
            u)
                if [ -f "$3" ]; then
                    update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILE_SCREEN}" "arm-screen" "pkill -9 arm-screen" ""
                else
                    update_program "$3" "/userdata/arm-agent/bin/" "${FILE_SCREEN}" "arm-screen" "pkill -9 arm-screen" ""
                fi
                ;;
            *)
                show_help
                ;;
        esac
        ;;
     input)
        case "$2" in
            m)
                update_git_branch "${FILEPATH_INPUT_DEVICE_SERVICE}" "$3" "make_package ${FILEPATH_INPUT_DEVICE_SERVICE}"
                ;;
            u)
                if [ -f "$3" ]; then
                    update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILE_INPUT}" "input-dev-server" "" "systemctl restart input-device"
                else
                    update_program "$3" "/userdata/arm-agent/bin/" "${FILE_INPUT}" "input-dev-server" "" "systemctl restart input-device"
                fi
                ;;
            *)
                show_help
                ;;
        esac
        ;;
    img)
        case "$2" in
            u)
                if [ -f "$3" ]; then
                    update_images_batch "$3" "$4"
                else
                    update_image "$3" "$4"
                fi
                ;;
            *)
                show_help
                ;;
        esac
        ;;
    all)
        if [ "$2" = "u" ] && [ -n "$3" ]; then
            if [ -f "$3" ]; then
                update_from_file_parallel "$3" "/userdata/arm-agent/libs/" "${FILE_MEDIA}" "libmedia_server.so" "" ""
                update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILE_STREAM}" "arm-stream" "pkill arm-stream" ""
                update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILE_AGENT}" "arm-agent" "systemctl stop arm-agent" "systemctl start arm-agent"
                update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILE_SCREEN}" "arm-screen" "pkill -9 arm-screen" ""
                update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILE_INPUT}" "input-device" "" "systemctl restart input-device"
		        update_from_file_parallel "$3" "/userdata/arm-agent/bin/" "${FILEPATH_MANAGE_SHELL}" "manage-shell" "systemctl stop arm-agent; docker stop \$(docker ps -aq); docker rm \$(docker ps -aq)" "systemctl start arm-agent"
            else
                update_program "$3" "/userdata/arm-agent/libs/" "${FILE_MEDIA}" "libmedia_server.so" "" ""
                update_program "$3" "/userdata/arm-agent/bin/" "${FILE_STREAM}" "arm-stream" "pkill arm-stream" ""
                update_program "$3" "/userdata/arm-agent/bin/" "${FILE_AGENT}" "arm-agent" "systemctl stop arm-agent" "systemctl start arm-agent"
                update_program "$3" "/userdata/arm-agent/bin/" "${FILE_SCREEN}" "arm-screen" "pkill -9 arm-screen" ""
                update_program "$3" "/userdata/arm-agent/bin/" "${FILE_INPUT}" "input-dev-server" "" "systemctl restart input-device"
		        update_program "$3" "/userdata/arm-agent/bin/" "${FILEPATH_MANAGE_SHELL}" "manage-shell" "systemctl stop arm-agent; docker stop \$(docker ps -aq); docker rm \$(docker ps -aq)" "systemctl start arm-agent"
            fi
        else
            show_help
        fi
        ;;
    *)
        show_help
        ;;
esac

log_info "脚本执行完毕"
