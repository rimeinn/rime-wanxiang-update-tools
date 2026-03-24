#!/usr/bin/env bash

set -euo pipefail

#### 配置 Rime 输入法引擎 ####
# 支持鼠须管或小企鹅
# 例如 "fcitx5"
# 例如 "squirrel"
ENGINE=""

######### 配置结束 #########

# 全局变量
CNB_API="https://cnb.cool/amzxyz/rime-wanxiang/-/releases"
SCHEMA_API="https://api.github.com/repos/amzxyz/rime_wanxiang/releases"
GRAM_API="https://api.github.com/repos/amzxyz/RIME-LMDG/releases"
TOOLS_API="https://api.github.com/repos/rimeinn/rime-wanxiang-update-tools/releases"
FUZHU_LIST=("base" "flypy" "hanxin" "moqi" "tiger" "wubi" "zrm" "shouyou")
TEMP_DIR=$(mktemp -d /tmp/wanxiang-update-XXXXXX)
UPDATE_TOOLS_VERSION="DEFAULT_UPDATE_TOOLS_VERSION_TAG"

# 日志与错误处理
log() {
  local red="\033[0;31m" green="\033[0;32m" yellow="\033[0;33m" nc="\033[0m"
  local level="$1" color="$nc"
  case "$level" in
  INFO) color="$green" ;;
  WARN) color="$yellow" ;;
  ERROR) color="$red" ;;
  esac
  shift
  printf "${color}[%s] %s${nc}\n" "$level" "$*"
}

# 获取当前脚本名称
script_name=$(basename $0)
script_dir=$(pwd)

engine_check() {
# 输入法引擎检测
if [ -z "$ENGINE" ]; then
  log ERROR "当前未配置输入法引擎"
  log WARN "如果使用Fcitx5（小企鹅）输入法，请复制以下语句并按回车执行，结束后请重新运行脚本："
  echo "sed -i '' 's/ENGINE=\"\"/ENGINE=\"fcitx5\"/g' ${script_dir}/${script_name}"
  log WARN  "如果使用Squirrel（鼠须管）输入法，请复制以下语句并按回车执行，结束后请重新运行脚本："
  echo "sed -i '' 's/ENGINE=\"\"/ENGINE=\"squirrel\"/g' ${script_dir}/${script_name}"
  exit
elif [ "$ENGINE" == "fcitx5" ]; then
  log INFO "当前使用Fcitx5（小企鹅）输入法"
  read -rp "按回车继续，M 键更改: " if_modify
  if [ "$if_modify" == "M" ]; then
  log WARN "请复制以下语句并按回车执行，结束后请重新运行脚本："
  echo "sed -i '' 's/ENGINE=\"fcitx5\"/ENGINE=\"squirrel\"/g' ${script_dir}/${script_name}"
  exit
  fi
elif [ "$ENGINE" == "squirrel" ]; then
  log INFO "当前使用squirrel（鼠须管）输入法"
  read -rp "按回车继续，M 键更改: " if_modify
  if [ "$if_modify" == "M" ]; then
  log WARN "请复制以下语句并按回车执行，结束后请重新运行脚本："
  echo "sed -i '' 's/ENGINE=\"squirrel\"/ENGINE=\"fcitx5\"/g' ${script_dir}/${script_name}"
  exit
  fi
fi
}

error_exit() {
  log ERROR "$*"
  cleanup
  exit 1
}
cleanup() {
  if [[ -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR" || log WARN "清理缓存文件失败"
  fi
}
deps_check() {
  for _cmd in curl jq unzip; do
    command -v "$_cmd" >/dev/null || error_exit "缺少必要依赖：$_cmd"
  done
}
fuzhu_check() {
  local fuzhu_check="$1"
  for _fuzhu in "${FUZHU_LIST[@]}"; do
    if [[ "$fuzhu_check" == "$_fuzhu" ]]; then
      return 0
    fi
  done
  return 1
}
script_check() {
  local mirror="$1"
  if [[ "$UPDATE_TOOLS_VERSION" =~ ^"DEFAULT" ]]; then
    log WARN "您似乎正在使用源文件！"
    log WARN "请从 Release 页面下载正式版！"
    error_exit "终止操作"
  fi
  log INFO "工具当前版本 $UPDATE_TOOLS_VERSION"
  if [[ "$mirror" == "github" ]]; then
    # 检查 GitHub 连接状态
    log INFO "正在检查 GitHub 连接状态"
    if ! curl -sL --connect-timeout 5 "https://api.github.com" >/dev/null; then
      error_exit "您似乎无法连接到 GitHub API, 请检查您的网络"
    elif ! curl -sL --connect-timeout 5 "https://github.com" >/dev/null; then
      error_exit "您似乎无法连接到 GitHub, 请检查您的网络"
    fi
    log INFO "正在检查本工具是否存在更新"
    local local_version remote_version
    local_version="$UPDATE_TOOLS_VERSION"
    remote_version=$(
      curl -sL --connect-timeout 10 $TOOLS_API |
        jq -r '.[].tag_name' | grep -vE "rc" | sort -rV | head -n 1
    )
    if [[ "$remote_version" > "$local_version" ]]; then
      log WARN "检测到工具最新版本为: $remote_version, 建议更新后继续"
      log WARN "https://github.com/rimeinn/rime-wanxiang-update-tools/releases/download/$remote_version/rime-wanxiang-update-macos.sh"
    else
      log INFO "工具已是最新版本"
    fi
  elif [[ "$mirror" == "cnb" ]]; then
    log WARN "由于您正在使用镜像，无法检查本工具是否存在更新"
  fi
}

get_info() {
  local mirror="$1" version="$2" name="$3" type="${4:-}" info
  if [[ "$mirror" == "github" ]]; then
    info=$(
      jq -r --arg version "$version" --arg name "$name" --arg type "$type" '
        .[] |
        select(.tag_name == $version) |
        .assets[] |
        select(.name | test($name)) |
        select(
          (($name != "gram") or (.name | contains("mini") | not))
          and
          (($type != "dicts") or (.name | contains("dicts")))
        )
      ' "$TEMP_DIR/github_$name.json"
    )
    echo "$info"
  elif [[ "$mirror" == "cnb" ]]; then
    info=$(
      jq -r --arg version "refs/tags/$version" --arg name "$name" --arg type "$type" '
        .releases[] |
        select(.tag_ref == $version) |
        .assets[] |
        select(.name | test($name)) |
        select(
          (($type != "dicts") or (.name | contains("dicts")))
        )
      ' "$TEMP_DIR/cnb_$name.json"
    )
    echo "$info"
  fi
}

# 排除文件检查
# 函数：检查文件是否存在，如果不存在则创建并写入指定内容
create_exclude_file() {
  local file="${DEPLOY_DIR}/custom/user_exclude_file.txt"

  if [[ -z "$file" ]]; then
    error_exit "错误：必须指定排除文件路径"
  fi

  if [[ -f "$file" ]]; then
    echo "排除文件已存在：$file"
  else
    echo "排除文件不存在，正在创建：$file"
    # 确保目录存在
    mkdir -p "$(dirname "$file")"
    # 创建并写入内容
    cat > "$file" <<EOF
# 排除文件本身（请勿删除）
custom/user_exclude_file.txt
# 用户数据库
lua/sequence.userdb
lua/sequence.txt
lua/input_stats.lua
zc.userdb
# 同步
installation.yaml
user.yaml
# custom文件
default.custom.yaml
wanxiang_pro.custom.yaml
wanxiang_reverse.custom.yaml
wanxiang_mixedcode.custom.yaml
# ##############以上内容请在了解万象方案机制后自行更改，否则请不要更改##############
EOF
  fi
}
apply() {
  local source_dir="$1"
  local base_dir="${2:-$source_dir}"  # 基准目录，默认为第一个参数，$2和$source_dir哪个不为空就取哪个

  # 计算目标路径
  local relative_path="${source_dir#$base_dir}" # 从source_dir删除开头的base_dir部分
  local target_path="$DEPLOY_DIR/${relative_path:+$relative_path/}" # relative_path不为空则使用relative_path，否则使用空值

  # 确保目标目录存在
  mkdir -p "$target_path"

  # 处理当前目录的文件和子目录
  for item in "$source_dir"/*; do
    if [[ -f "$item" ]]; then
	  # 复制解压出来的文件到目标路径
      cp -f "$item" "$target_path"
    elif [[ -d "$item" ]]; then
      # 处理子目录
      apply "$item" "$base_dir"
    fi
  done
}
# 获取更新的版本号
get_newer() {
    echo "$1 $2" | tr ' ' '\n' | sed 's/^v//' | sort -V | tail -n1 | sed 's/^/v/'
}
update_schema() {
  local mirror="$1" fuzhu="$2" gram="$3"
  # 缓存 API 响应
  if [[ "$mirror" == "github" ]]; then
    if [[ ! -f "$TEMP_DIR/github_$fuzhu.json" ]]; then
      if ! curl -sL -H "Accept: application/vnd.github.v3+json" \
        --connect-timeout 10 "$SCHEMA_API" >"$TEMP_DIR/github_$fuzhu.json"; then
        error_exit "连接到 GitHub API 失败，您可能需要检查网络"
      fi
    fi
  elif [[ "$mirror" == "cnb" ]]; then
    if [[ ! -f "$TEMP_DIR/cnb_$fuzhu.json" ]]; then
      if ! curl -sL -H "accept: application/vnd.cnb.web+json" \
        --connect-timeout 10 "$CNB_API" >"$TEMP_DIR/cnb_$fuzhu.json"; then
        error_exit "连接到 CNB 失败，您可能需要检查网络"
      fi
    fi
  fi
  # 获取本地版本号
  local local_version remote_version
  if [[ -f "$DEPLOY_DIR/version.txt" ]]; then
    local_version=$(cat "$DEPLOY_DIR/version.txt")
    [[ "$local_version" == v* ]] || local_version="v$local_version"
  else
    local_version="v0"
  fi
  # 获取远程版本号
  if [[ "$mirror" == "github" ]]; then
    remote_version=$(
      jq -r '.[].tag_name' "$TEMP_DIR/github_$fuzhu.json" |
        grep -vE "dict-nightly" | sort -rV | head -n 1
    )
  elif [[ "$mirror" == "cnb" ]]; then
    remote_version=$(
      jq -r '.releases.[].tag_ref' \
        "$TEMP_DIR/cnb_$fuzhu.json" | grep -vE "model" | sort -rV | head -n 1
    )
    remote_version="${remote_version#"refs/tags/"}"
  fi
  [[ "$remote_version" == v* ]] || remote_version="v$remote_version"
  newer=$(get_newer $remote_version $local_version)
  if [[ "$local_version" != "$newer" ]]; then
    log INFO "远程方案文件版本号为 $remote_version, 以下内容为更新日志"
    local changelog
    if [[ "$mirror" == "github" ]]; then
      changelog=$(
        jq -r --arg version "$remote_version" '.[] |
        select( .tag_name == $version ) | .body' "$TEMP_DIR/github_$fuzhu.json"
      )
    elif [[ "$mirror" == "cnb" ]]; then
      changelog=$(
        jq -r --arg version "refs/tags/$remote_version" '.releases.[] |
        select( .tag_ref == $version ) | .body' "$TEMP_DIR/cnb_$fuzhu.json"
      )
    fi
    echo -e "$changelog" | sed -n '/## 📝 更新日志/,/## 🚀 下载引导/p' | sed '$d'
    sleep 3
    log INFO "开始更新方案文件，正在下载文件"
    local schemaurl schemaname local_size remote_size
    if [[ "$mirror" == "github" ]]; then
      schemaurl=$(get_info "$mirror" "$remote_version" "$fuzhu" | jq -r '.browser_download_url')
    elif [[ "$mirror" == "cnb" ]]; then
      schemaurl=$(get_info "$mirror" "$remote_version" "$fuzhu" | jq -r '.path')
      schemaurl="https://cnb.cool$schemaurl"
    fi
    schemaname=$(get_info "$mirror" "$remote_version" "$fuzhu" | jq -r '.name')
    curl -L --connect-timeout 10 -o "$TEMP_DIR/$schemaname" "$schemaurl"
    log INFO "正在验证文件完整性"
    local_size=$(stat -f %z "$TEMP_DIR/$schemaname")
    if [[ "$mirror" == "github" ]]; then
      remote_size=$(get_info "$mirror" "$remote_version" "$fuzhu" | jq -r '.size')
    elif [[ "$mirror" == "cnb" ]]; then
      remote_size=$(get_info "$mirror" "$remote_version" "$fuzhu" | jq -r '.size_in_byte')
    fi
    if [[ "$local_size" != "$remote_size" ]]; then
      log ERROR "期望文件大小: $remote_size, 实际文件大小: $local_size"
      error_exit "方案文件下载出错，请重试！"
    fi
    log INFO "验证成功，开始更新方案文件"
    unzip -q "$TEMP_DIR/$schemaname" -d "$TEMP_DIR/${schemaname%.zip}"
    for _file in "简纯+.trime.yaml" "custom_phrase.txt" "squirrel.yaml" "weasel.yaml"; do
      if [[ -f "$TEMP_DIR/${schemaname%.zip}/$_file" ]]; then
        rm -r "$TEMP_DIR/${schemaname%.zip}/${_file:?}"
      fi
    done
    local exclude_file
    while IFS= read -r _line; do
      if [[ "$_line" != \#* ]]; then
        exclude_file="$_line"
        if [[ -e "$TEMP_DIR/$exclude_file" ]]; then
          log WARN "项目 $TEMP_DIR/$exclude_file 为排除文件不更新"
          rm -rf "$TEMP_DIR/$exclude_file"
        fi
      fi
    done <"$DEPLOY_DIR/custom/user_exclude_file.txt"

    # 应用更新
    apply "$TEMP_DIR/${schemaname%.zip}"
    log INFO "方案文件更新成功"
    return 0
  else
    log INFO "远程方案文件版本号为 $remote_version"
    log INFO "本地方案文件版本号为 $local_version, 您目前无需更新它"
    return 1
  fi
}
update_dict() {
    local mirror="$1" fuzhu_input="$2"
    local fuzhu
    if [[ "$fuzhu_input" == "base" ]]; then
        fuzhu="base-dicts"
    else
        fuzhu="${fuzhu_input}-fuzhu-dicts"
    fi
  # 缓存 API 响应
  if [[ "$mirror" == "github" ]]; then
    if [[ ! -f "$TEMP_DIR/github_$fuzhu.json" ]]; then
      if ! curl -sL -H "Accept: application/vnd.github.v3+json" \
        --connect-timeout 10 "$SCHEMA_API" >"$TEMP_DIR/github_$fuzhu.json"; then
        error_exit "连接到 GitHub API 失败，您可能需要检查网络"
      fi
    fi
  elif [[ "$mirror" == "cnb" ]]; then
    if [[ ! -f "$TEMP_DIR/cnb_$fuzhu.json" ]]; then
      if ! curl -sL -H "accept: application/vnd.cnb.web+json" \
        --connect-timeout 10 "$CNB_API" >"$TEMP_DIR/cnb_$fuzhu.json"; then
        error_exit "连接到 CNB 失败，您可能需要检查网络"
      fi
    fi
  fi
  local local_date remote_date
  if [[ -f "$DEPLOY_DIR/dicts/cn&en.dict.yaml" ]]; then
    local_date=$(stat -f %m "$DEPLOY_DIR/dicts/cn&en.dict.yaml")
  else
    local_date=0
  fi
  if [[ "$mirror" == "github" ]]; then
    remote_date=$(get_info "$mirror" "dict-nightly" "$fuzhu" "dicts" | jq -r '.updated_at')
  elif [[ "$mirror" == "cnb" ]]; then
    remote_date=$(get_info "$mirror" "v1.0.0" "$fuzhu" "dicts" | jq -r '.updated_at')
  fi
  remote_date=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$remote_date" +%s)
  if [[ $remote_date -gt $local_date ]]; then
    log INFO "正在下载最新词典文件"
    local dicturl dictname local_size remote_size
    if [[ "$mirror" == "github" ]]; then
      dicturl=$(get_info "$mirror" "dict-nightly" "$fuzhu" "dicts" | jq -r '.browser_download_url')
      dictname=$(get_info "$mirror" "dict-nightly" "$fuzhu" "dicts" | jq -r '.name')
    elif [[ "$mirror" == "cnb" ]]; then
      dicturl=$(get_info "$mirror" "v1.0.0" "$fuzhu" "dicts" | jq -r '.path')
      dicturl="https://cnb.cool$dicturl"
      dictname=$(get_info "$mirror" "v1.0.0" "$fuzhu" "dicts" | jq -r '.name')
    fi
    curl -L --connect-timeout 10 -o "$TEMP_DIR/$dictname" "$dicturl"
    log INFO "正在验证文件完整性"
    local_size=$(stat -f %z "$TEMP_DIR/$dictname")
    if [[ "$mirror" == "github" ]]; then
      remote_size=$(get_info "$mirror" "dict-nightly" "$fuzhu" "dicts" | jq -r '.size')
    elif [[ "$mirror" == "cnb" ]]; then
      remote_size=$(get_info "$mirror" "v1.0.0" "$fuzhu" "dicts" | jq -r '.size_in_byte')
    fi
    if [[ "$local_size" != "$remote_size" ]]; then
      log ERROR "期望文件大小: $remote_size, 实际文件大小: $local_size"
      error_exit "词典文件下载出错，请重试！"
    fi
    log INFO "验证成功，开始更新词典文件"
    unzip -q "$TEMP_DIR/$dictname" -d "$TEMP_DIR/${dictname%.zip}"
    mkdir -p "$DEPLOY_DIR/dicts"
    if [[ -e "$TEMP_DIR/${dictname%.zip}/${dictname%.zip}" ]]; then
      cp -rf "$TEMP_DIR/${dictname%.zip}/${dictname%.zip}/"* "$DEPLOY_DIR/dicts/"
    else
      cp -rf "$TEMP_DIR/${dictname%.zip}/"* "$DEPLOY_DIR/dicts/"
    fi
    log INFO "词典文件更新成功"
    return 0
  else
    remote_date=$(date -r "$remote_date" +"%Y-%m-%d %H:%M:%S")
    log INFO "远程词典文件最后更新于 $remote_date"
    local_date=$(date -r "$local_date" +"%Y-%m-%d %H:%M:%S")
    log INFO "本地词典文件最后更新于 $local_date, 您目前无需更新它"
    return 1
  fi
}
update_gram() {
  local mirror="$1"
  # 缓存 API 响应
  if [[ "$mirror" == "github" ]]; then
    if [[ ! -f "$TEMP_DIR/github_gram.json" ]]; then
      if ! curl -sL -H "Accept: application/vnd.github.v3+json" \
        --connect-timeout 10 "$GRAM_API" >"$TEMP_DIR/github_gram.json"; then
        error_exit "连接到 GitHub API 失败，您可能需要检查网络"
      fi
    fi
  elif [[ "$mirror" == "cnb" ]]; then
    if [[ ! -f "$TEMP_DIR/cnb_gram.json" ]]; then
        headers=$(curl -sL -D - -o /dev/null -H "accept: application/vnd.cnb.web+json" "$CNB_API")
        X_CNB_TOTAL=$(echo "$headers" | awk -F': ' '/[Xx]-[Cc]nb-[Tt]otal:/ {gsub(/ /,"",$2); print $2}')
        X_CNB_PAGE_SIZE=$(echo "$headers" | awk -F': ' '/[Xx]-[Cc]nb-[Pp]age-[Ss]ize:/ {gsub(/ /,"",$2); print $2}')
        # 防止为空
        X_CNB_TOTAL=${X_CNB_TOTAL:-0}
        X_CNB_PAGE_SIZE=${X_CNB_PAGE_SIZE:-1}
        # 确保是数字
        X_CNB_TOTAL=$(echo "$X_CNB_TOTAL" | tr -d -c 0-9)
        X_CNB_PAGE_SIZE=$(echo "$X_CNB_PAGE_SIZE" | tr -d -c 0-9)
        # 获取最后一页
        last_page=$(( (X_CNB_TOTAL + X_CNB_PAGE_SIZE - 1) / X_CNB_PAGE_SIZE ))

        if ! curl -G -sL -H "accept: application/vnd.cnb.web+json" \
            --data-urlencode "page=${last_page}" \
            --connect-timeout 10 "$CNB_API" >"$TEMP_DIR/cnb_gram.json"; then
            error_exit "连接到 CNB 失败，您可能需要检查网络"
        fi
    fi
  fi
  local local_date remote_date gramname="wanxiang-lts-zh-hans.gram"
  if [[ -f "$DEPLOY_DIR/$gramname" ]]; then
    local_date=$(stat -f %m "$DEPLOY_DIR/$gramname")
  else
    local_date=0
  fi
  if [[ "$mirror" == "github" ]]; then
    remote_date=$(get_info "$mirror" "LTS" "gram" | jq -r '.updated_at')
  elif [[ "$mirror" == "cnb" ]]; then
    remote_date=$(get_info "$mirror" "model" "gram" | jq -r '.updated_at')
  fi
  remote_date=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$remote_date" +%s)
  if [[ $remote_date -gt $local_date ]]; then
    log INFO "正在下载最新语法模型"
    local gramurl local_size remote_size
    if [[ "$mirror" == "github" ]]; then
      gramurl=$(get_info "$mirror" "LTS" "gram" | jq -r '.browser_download_url')
    elif [[ "$mirror" == "cnb" ]]; then
      gramurl=$(get_info "$mirror" "model" "gram" | jq -r '.path')
      gramurl="https://cnb.cool$gramurl"
    fi
    curl -L --connect-timeout 10 -o "$TEMP_DIR/$gramname" "$gramurl"
    log INFO "正在验证文件完整性"
    local_size=$(stat -f %z "$TEMP_DIR/$gramname")
    if [[ "$mirror" == "github" ]]; then
      remote_size=$(get_info "$mirror" "LTS" "gram" | jq -r '.size')
    elif [[ "$mirror" == "cnb" ]]; then
      remote_size=$(get_info "$mirror" "model" "gram" | jq -r '.size_in_byte')
    fi
    if [[ "$local_size" != "$remote_size" ]]; then
      log ERROR "期望文件大小: $remote_size, 实际文件大小: $local_size"
      error_exit "语法模型下载出错，请重试！"
    fi
    log INFO "验证成功，开始更新语法模型"
    cp -rf "$TEMP_DIR/$gramname" "${DEPLOY_DIR}/$gramname"
    log INFO "语法模型更新成功"
    return 0
  else
    remote_date=$(date -r "$remote_date" +"%Y-%m-%d %H:%M:%S")
    log INFO "远程语法模型最后更新于 $remote_date"
    local_date=$(date -r "$local_date" +"%Y-%m-%d %H:%M:%S")
    log INFO "本地语法模型最后更新于 $local_date, 您目前无需更新它"
    return 1
  fi
}
# 部属函数
deploy() {
  local deploy_executable="$1"
  shift # 移除第一个参数，后续所有参数都是要传给可执行文件的
  if [ -x "$deploy_executable" ]; then
  echo "正在触发重新部署配置"
    if output_and_error=$("$deploy_executable" "$@" 2>&1); then
      [[ -n "$output_and_error" ]] && echo "输出: $output_and_error"
      echo "重新部署成功"
    else
      echo "重新部署失败"
      [[ -n "$output_and_error" ]] && echo "错误信息: $output_and_error"
    fi
  else
    echo "找不到可执行文件: $deploy_executable"
    echo "请手动部署"
  fi
}
show_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

选项:
  --mirror [github|cnb]        选择下载源 (默认: github)
  --engine [fcitx5|squirrel]   设置输入法引擎 (必需，也可在脚本中设置对应变量)
  --schema [base|pro]          更新方案类型
  --fuzhu SCHEMA               更新辅助码表 (base|flypy|hanxin|moqi|tiger|wubi|zrm|shouyou)
  --dict                       更新词典
  --gram                       更新语法模型
  --help                       显示此帮助信息

示例:
  $0 --engine squirrel --schema base --fuzhu base --dict
  $0 --mirror cnb --engine squirrel --schema pro --fuzhu flypy --gram

注意:
  必须至少指定一个更新项目: --schema, --dict 或 --gram
  使用 --schema 或 --dict 时必须同时使用 --fuzhu
EOF
}
main() {
  # 脚本退出清理临时目录
  trap cleanup EXIT
  # 欢迎语
  log INFO "欢迎使用万象方案更新助手"
  # 检查是否为root用户
  if [[ "$EUID" -eq 0 ]]; then
    error_exit "请不要使用 root 身份运行该脚本！"
  fi
  # 检查必要的依赖
  deps_check
  # 处理用户输入
  local mirror="" schema="" fuzhu="" dict="false" gram="false"
  # 解析命令行参数
  while [[ "$#" -gt 0 ]]; do
    case $1 in
    --mirror)
      if [[ -n "$mirror" ]]; then
        error_exit "选项 mirror 需要参数！"
      else
        shift
      fi
      if [[ "$1" != "cnb" ]]; then
        error_exit "选项 mirror 的参数目前只能为 cnb"
      else
        mirror="$1"
      fi
      ;;
    --engine)
      if [[ -n "$ENGINE" ]]; then
        error_exit "选项 engine 已指定！"
      fi
      shift
      if [[ -z "$1" || "$1" == --* ]]; then
        error_exit "选项 engine 需要参数！"
      fi
      if [[ "$1" != "fcitx5" && "$1" != "squirrel" ]]; then
        error_exit "选项 engine 的参数只能为 fcitx5 或 squirrel"
      fi
      ENGINE="$1"
      ;;
    --schema)
      if [[ -n "$schema" ]]; then
        error_exit "选项 schema 需要参数！"
      else
        shift
      fi
      if [[ "$1" != "base" && "$1" != "pro" ]]; then
        error_exit "选项 schema 的参数只能为 base 或 pro"
      else
        schema="$1"
      fi
      ;;
    --fuzhu)
      if [[ -n "$fuzhu" ]]; then
        error_exit "选项 fuzhu 需要参数！"
      else
        shift
      fi
      if fuzhu_check "$1"; then
        fuzhu="$1"
      else
        error_exit "选项 fuzhu 的参数只能为 ${FUZHU_LIST[*]} 其中之一"
      fi
      ;;
    --dict)
      dict="true"
      ;;
    --gram)
      gram="true"
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      log WARN "未知参数: $1"
      log WARN "使用 --help 查看帮助信息"
      error_exit "参数输入错误: $1"
      ;;
    esac
    shift
  done

  engine_check
  # 获取输入法配置路径
  if [ "$ENGINE" = "fcitx5" ]; then
    DEPLOY_DIR="$HOME/.local/share/fcitx5/rime"
  else
    DEPLOY_DIR="$HOME/Library/Rime"
  fi

  # 判断是否设置了部署目录
  if [[ -n "$DEPLOY_DIR" ]]; then
    if [[ ! -d "$DEPLOY_DIR" ]]; then
      log WARN "部署目录 $DEPLOY_DIR 不存在，您要创建它吗？"
      read -rp "请输入 YES 或 NO (区分大小写) " _check
      if [[ "$_check" == "YES" ]]; then
        log WARN "您真的要创建该目录吗？您确定您的设置正确吗？"
        read -rp "请输入 YES 或 NO (区分大小写) " _check_again
        [[ "$_check_again" == "YES" ]] || error_exit "用户终止操作"
        mkdir -p "$DEPLOY_DIR"
      else
        error_exit "用户终止操作"
      fi
    fi
  else
    error_exit "请设置部署目录！"
  fi
  # 排除项目列表文件是否存在
  if [[ -f "$DEPLOY_DIR/user_exclude_file.txt" ]]; then
    mv "$DEPLOY_DIR/user_exclude_file.txt" "$DEPLOY_DIR/custom/user_exclude_file.txt"
    sed -i 's/user_exclude_file\.txt/custom\/user_exclude_file\.txt/g' \
      "$DEPLOY_DIR/custom/user_exclude_file.txt"
  fi
  if [[ ! -f "$DEPLOY_DIR/custom/user_exclude_file.txt" ]]; then
    log WARN "您没有设置排除项目列表！"
    log WARN "将为您自动创建包含部分排除项目列表文件： $DEPLOY_DIR/custom/user_exclude_file.txt"
    # 生成排除文件
    create_exclude_file
    log INFO "排除项目列表文件已创建"
    log WARN "您还可以在该文件中写入您需要排除的项目，每行一个"
    read -rp "按回车继续，M 键更改: " if_modify
    if [ "$if_modify" == "M" ]; then
    log WARN "请修改排除项目列表文件： $DEPLOY_DIR/custom/user_exclude_file.txt"
    log WARN "保存后重新运行该脚本"
    open "$DEPLOY_DIR/custom/user_exclude_file.txt"
    exit
    fi
  fi
  # 检查 schema 和 fuzhu 是否同时存在
  if [[ -n "$schema" && -z "$fuzhu" ]]; then
    error_exit "选项 schema 与选项 fuzhu 必须同时使用"
  fi
  # 检查 dict 和 fuzhu 是否同时存在
  if [[ "$dict" == "true" && -z "$fuzhu" ]]; then
    error_exit "选项 dict 与选项 fuzhu 必须同时使用"
  fi
  # 检查当 schema 为 base 时，fuzhu 是否也为 base
  if [[ "$schema" == "base" && "$fuzhu" != "base" ]]; then
    error_exit "当选项 schema 为 base 时，选项 fuzhu 必须为 base"
  fi
  [[ -n "$mirror" ]] || mirror="github"
  # 脚本自检
  script_check "$mirror"
  # 开始更新
  updated=false
  [[ -z "$schema" ]] || {
    update_schema "$mirror" "$fuzhu" "$gram" && updated=true
  }
  [[ "$dict" == "false" ]] || {
    update_dict "$mirror" "$fuzhu" && updated=true
  }
  [[ "$gram" == "false" ]] || {
    update_gram "$mirror" && updated=true
  }
  # 自动部署
  if [ "$updated" = true ]; then
    if [ "$ENGINE" = "squirrel" ]; then
      DEPLOY_EXECUTABLE="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
      deploy "$DEPLOY_EXECUTABLE" --reload
    else
      DEPLOY_EXECUTABLE="/Library/Input Methods/Fcitx5.app/Contents/bin/fcitx5-curl"
      deploy "$DEPLOY_EXECUTABLE" /config/addon/rime/deploy -X POST -d '{}'
    fi
  fi
}

main "$@"
