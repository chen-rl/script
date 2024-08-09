#!/bin/bash

# 打包目录
local_directory_stream="/data/build-test/arm-stream"
local_directory_media="/data/build-test/arm-stream"
local_directory_agent="/data/build-test/arm-agent"
local_directory_manage="/data/build-test/manage-shell"
local_directory_screen="/data/build-test/capture-screen"
# 获得最新文件和目录
fileName_stream=$(ls -t /data/build-test/arm-stream/build/arm-stream* | head -1)
fileName_media=$(ls -t /data/build-test/arm-stream/media_server/lib/libmedia_server.so.1.* | head -1)
fileName_agent=$(ls -t /data/build-test/arm-agent/bin/ | head -1)
fileName_screen=$(ls -t /data/build-test/capture-screen/bin/arm-screen* | head -1)

#pathName_manage=$(ls -t /userdata/arm-agent/bin/ | grep manage-shell)


# 各种程序打包
# stream打包
make_package_stream() {
  # 打包
  cd $local_directory_media/media_server/build
#  rm /data/build-test/arm-stream/media_server/lib/libmedia_server.so.1.*
  cmake ..
  make -j
  echo "media打包完毕"
  cd $local_directory_stream/build
  cmake ..
  make -j
  echo "stream打包完毕"
}
# agent打包
make_package_agent() {
  # 打包
  cd $local_directory_agent/build
  cmake ..
  make -j
  echo "agent打包完毕"
}
# screen
make_package_screen() {
  # 打包
  cd $local_directory_screen/build
  cmake ..
  make -j
  echo "screen打包完毕"
}
# 更新设备程序
ip=$3
echo "连接 $ip..."
# 更新物理机stream和media
update_stream(){
  sshpass -p 'root' ssh root@$ip "rm /userdata/arm-agent/libs/libmedia_server*"
  sshpass -p 'root' scp -r $fileName_media root@$ip:/userdata/arm-agent/libs/
  sshpass -p 'root' ssh root@$ip "ln -sf /userdata/arm-agent/libs/libmedia_server.so.1* /userdata/arm-agent/libs/libmedia_server.so.1"
  sshpass -p 'root' ssh root@$ip "rm /userdata/arm-agent/bin/arm-stream*"
  sshpass -p 'root' scp $fileName_stream root@$ip:/userdata/arm-agent/bin/
  sshpass -p 'root' ssh root@$ip "pkill arm-stream"
  sshpass -p 'root' ssh root@$ip "ln -sf  /userdata/arm-agent/bin/arm-stream* /userdata/arm-agent/bin/arm-stream"
  echo "更新stream完成" $ip
}
# 更新agent
update_agent(){
  # 使用ssh连接到每个IP并执行命令
  sudo sshpass -p "root" ssh root@$ip "systemctl stop arm-agent; rm -r /userdata/arm-agent/bin/arm-agent*"
  sudo sshpass -p "root" scp -r /data/build-test/arm-agent/bin/$fileName_agent root@$ip:/userdata/arm-agent/bin/
  sudo sshpass -p "root" ssh root@$ip "ln -sf /userdata/arm-agent/bin/arm-agent.* /userdata/arm-agent/bin/arm-agent"
#  sudo sshpass -p "root" ssh root@$2 "sed -i 's#192.168.168.167#192.168.168.145#g' '/userdata/arm-agent/conf/arm-agentConfig.json'"
  sudo sshpass -p "root" ssh root@$ip "systemctl start arm-agent"
  echo "更新agent完成" $ip
}
# 更新manage-shell
update_manage() {
  sshpass -p 'root' scp -r $local_directory_manage root@$ip:/userdata/arm-agent/bin/
  sshpass -p 'root' ssh root@$ip 'systemctl stop arm-agent'
  sshpass -p 'root' ssh root@$ip "docker stop \$(docker ps -aq); docker rm \$(docker ps -aq)"
#  sshpass -p 'root' ssh root@$ip "docker rm \$(docker ps -aq)"
  sshpass -p 'root' ssh root@$ip "systemctl start arm-agent"
  echo "更新manage-shell完成" $ip
}
# 更新screen
update_screen(){
  sshpass -p 'root' ssh root@$ip "rm /userdata/arm-agent/bin/arm-screen*"
  sshpass -p 'root' scp $fileName_screen root@$ip:/userdata/arm-agent/bin
  sshpass -p 'root' ssh root@$ip "pkill -9 arm-screen"
  sshpass -p 'root' ssh root@$ip "ln -sf /userdata/arm-agent/bin/arm-screen* /userdata/arm-agent/bin/arm-screen"
  echo "更新screen完成" $ip
}

# 更新分支以及打包
branch=$3
# 更新stream代码分支
update_git_stream(){
  rm -r $local_directory_stream/build/arm-stream*
#  rm /data/build-test/arm-stream/media_server/lib/libmedia_server.so.1.*
  # 删除CmakeCache文件
  rm /data/build-test/arm-stream/build/CMakeCache.txt
  rm /data/build-test/arm-stream/media_server/build/CMakeCache.txt
  #更新代码
  cd "$local_directory_stream" || exit
  git checkout .
  # 检查本地是否存在指定分支
  if git show-ref --verify --quiet "refs/heads/$branch"; then
      # 如果存在，切换到该分支
      echo "分支 $branch 存在，切换到该分支"
      git checkout "$branch"
      git pull
      make_package_stream
  else
   # 如果不存在，尝试从远程跟踪分支创建并切换
      if git ls-remote --exit-code origin "$branch" >/dev/null 2>&1; then
          # 如果远程存在，则创建并切换到该分支
          echo "本地不存在分支 $branch ， checkout新建"
          git fetch origin
          git checkout -b "$branch" "origin/$branch"
          make_package_stream
      else
          # 如果远程仓库也不存在，则报错
          echo "请检查输入的分支名是否正确"
          exit 1
      fi
  fi
}
# 更新agent
update_git_agent(){
  cd "$local_directory_agent" || exit
  git fetch origin
  # 检查本地是否存在指定分支
  if git show-ref --verify --quiet "refs/heads/$branch"; then
      # 如果存在，切换到该分支
      echo "分支 $branch 存在，切换到该分支"
      git checkout "$branch"
      git pull
      make_package_agent
  else
   # 如果不存在，尝试从远程跟踪分支创建并切换
      if git ls-remote --exit-code origin "$branch" >/dev/null 2>&1; then
          # 如果远程存在，则创建并切换到该分支
          echo "本地不存在分支 $branch ， checkout新建"
          git fetch origin
          git checkout -b "$branch" "origin/$branch"
          make_package_agent
      else
          # 如果远程也不存在，则报错
          echo "请检查输入的分支名是否正确"
          exit 1
      fi
  fi
}
# 更新manage-shell
update_git_manage(){
  #更新代码
  cd "$local_directory_manage" || exit
  # 检查本地是否存在指定分支
  if git show-ref --verify --quiet "refs/heads/$branch"; then
      # 如果存在，切换到该分支
      echo "分支 $branch 存在，切换到该分支"
      git checkout "$branch"
      git pull
  else
   # 如果不存在，尝试从远程跟踪分支创建并切换
      if git ls-remote --exit-code origin "$branch" >/dev/null 2>&1; then
          # 如果远程存在，则创建并切换到该分支
          echo "本地不存在分支 $branch ， checkout新建"
          git fetch origin
          git checkout -b "$branch" "origin/$branch"

      else
          # 如果远程也不存在，则报错
          echo "请检查输入的分支名是否正确"
          exit 1
      fi
  fi
}
update_git_screen(){
  #更新代码
  cd "$local_directory_screen" || exit
  # 检查本地是否存在指定分支
  if git show-ref --verify --quiet "refs/heads/$branch"; then
      # 如果存在，切换到该分支
      echo "分支 $branch 存在，切换到该分支"
      git checkout "$branch"
      git pull
      make_package_screen
  else
   # 如果不存在，尝试从远程跟踪分支创建并切换
      if git ls-remote --exit-code origin "$branch" >/dev/null 2>&1; then
          # 如果远程存在，则创建并切换到该分支
          echo "本地不存在分支 $branch ， checkout新建"
          git fetch origin
          git checkout -b "$branch" "origin/$branch"
          make_package_screen

      else
          # 如果远程也不存在，则报错
          echo "请检查输入的分支名是否正确"
          exit 1
      fi
  fi
}

# m是make  u是update意思
if [ "$1" = "stream" ] && [ "$2" = "m" ] && [ -n "$3" ]; then
    echo "打包stream，分支为"$branch
    update_git_stream
elif [ "$1" = "stream" ] && [ "$2" = "u" ] && [ -n "$3" ]; then
    echo "更新stream，设备ip为"$ip
    update_stream

elif [ "$1" = "agent" ] && [ "$2" = "m" ] && [ -n "$3" ]; then
    echo "打包agent，分支为"$branch
    update_git_agent
elif [ "$1" = "agent" ] && [ "$2" = "u" ] && [ -n "$3" ]; then
    echo "更新agent，设备ip为"$ip
    update_agent

elif [ "$1" = "
" ] && [ "$2" = "m" ] && [ -n "$3" ]; then
    echo "打包manage-shell，分支为"$branch
    update_git_manage
elif [ "$1" = "manage" ] && [ "$2" = "u" ] && [ -n "$3" ]; then
    echo "更新manage-shell，设备ip为"$ip
    update_manage

elif [ "$1" = "screen" ] && [ "$2" = "m" ] && [ -n "$3" ]; then
    echo "打包screen，分支为"$branch
    update_git_screen
elif [ "$1" = "screen" ] && [ "$2" = "u" ] && [ -n "$3" ]; then
    echo "更新screen，设备ip为"$ip
    update_screen

elif [ "$1" = "all" ] && [ "$2" = "u" ] && [ -n "$3" ]; then
    echo "更新stream、media、agent、manage-shell、screen，设备ip为"$ip
    update_stream
    update_agent
    update_screen
    update_manage
else
    echo "请检查输入的参数是否有误!"