#!/usr/bin/env bash

set -euo pipefail

#### 配置 Rime 输入法引擎 ####
# 支持鼠须管或小企鹅
# 例如 "fcitx5"
# 例如 "squirrel"
ENGINE=""


# 日志彩色输出
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NC="\033[0m"
readonly RED GREEN YELLOW NC

# 日志函数
log() {
  local level="$1" color="$NC"
  case "$level" in
  INFO) color="$GREEN" ;;
  WARN) color="$YELLOW" ;;
  ERROR) color="$RED" ;;
  esac
  shift
  printf "${color}[%s] %s${NC}\n" "$level" "$*"
}

# 获取当前脚本名称
script_name=$(basename $0)

# 输入法引擎检测
if [ -z "$ENGINE" ]; then
  log ERROR "当前未配置输入法引擎"
  log WARN "如果使用Fcitx5（小企鹅）输入法，请复制以下语句并按回车执行，结束后请重新运行脚本："
  echo "sed -i '' 's/ENGINE=\"\"/ENGINE=\"fcitx5\"/g' $script_name"
  log WARN  "如果使用Squirrel（鼠须管）输入法，请复制以下语句并按回车执行，结束后请重新运行脚本："
  echo "sed -i '' 's/ENGINE=\"\"/ENGINE=\"squirrel\"/g' $script_name"
  exit
elif [ "$ENGINE" == "fcitx5" ]; then
  log INFO "当前使用Fcitx5（小企鹅）输入法"
  read -rp "按回车继续，M 键更改: " if_modify
  if [ "$if_modify" == "M" ]; then
  log WARN "请复制以下语句并按回车执行，结束后请重新运行脚本："
  echo "sed -i '' 's/ENGINE=\"fcitx5\"/ENGINE=\"squirrel\"/g' $script_name"
  exit
  fi
elif [ "$ENGINE" == "squirrel" ]; then
  log INFO "当前使用squirrel（鼠须管）输入法"
  read -rp "按回车继续，M 键更改: " if_modify
  if [ "$if_modify" == "M" ]; then
  log WARN "请复制以下语句并按回车执行，结束后请重新运行脚本："
  echo "sed -i '' 's/ENGINE=\"squirrel\"/ENGINE=\"fcitx5\"/g' $script_name"
  exit
  fi
fi


# 获取输入法配置路径
if [ "$ENGINE" = "fcitx5" ]; then
  DEPLOY_DIR="$HOME/.local/share/fcitx5/rime"
else
  DEPLOY_DIR="$HOME/Library/Rime"
fi
######### 配置结束 #########

# 缓存文件
TEMP_DIR=$(mktemp -d /tmp/wanxiang-update.XXXXXX)
readonly DEPLOY_DIR TEMP_DIR

# 工具相关
TOOLS_DIR="$DEPLOY_DIR/update_tools_config"
CONFIG_FILE="$TOOLS_DIR/user_config.json"
UPDATE_FILE="$TOOLS_DIR/update_info.json"
RAW_DIR="$TOOLS_DIR/raw"
UPDATE_TOOLS_REPO="expoli/rime-wanxiang-update-tools"
UPDATE_TOOLS_VERSION="DEFAULT_UPDATE_TOOLS_VERSION_TAG"
readonly CONFIG_FILE UPDATE_FILE RAW_DIR UPDATE_TOOLS_REPO UPDATE_TOOLS_VERSION

# 仓库信息
SCHEMA_REPO="amzxyz/rime_wanxiang"
GRAM_REPO="amzxyz/RIME-LMDG"
GH_API="https://api.github.com/repos"
GH_DL="https://github.com"
readonly SCHEMA_REPO GRAM_REPO GH_API GH_DL


# 错误处理函数
error_exit() {
  log ERROR "$*"
  cleanup
  exit 1
}
# 清理临时文件
cleanup() {
  if [[ -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR" || log WARN "清理缓存文件失败"
  fi
}
# 检查必要依赖
check_deps() {
  for _cmd in curl unzip jq; do
    command -v "$_cmd" >/dev/null || error_exit "缺少必要依赖：$_cmd"
  done
}
# 获取 GitHub API 响应并缓存
get_github_response() {
  local type="$1" url
  case "$type" in
  tools) url="$GH_API/$UPDATE_TOOLS_REPO/releases" ;;
  schema) url="$GH_API/$SCHEMA_REPO/releases" ;;
  dict) url="$GH_API/$SCHEMA_REPO/releases" ;;
  gram) url="$GH_API/$GRAM_REPO/releases" ;;
  esac
  # 如果设置了 GITHUB_TOKEN 环境变量，使用认证头
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_header="Authorization: token $GITHUB_TOKEN"
    curl -sL --connect-timeout 5 -H "$auth_header" "$url" >"$TEMP_DIR/${type}_response.json"
  else
    curl -sL --connect-timeout 5 "$url" >"$TEMP_DIR/${type}_response.json"
  fi
  
  # 检查 curl 是否成功
  if [[ $? -ne 0 ]]; then
    error_exit "GitHub API 响应错误"
  fi
}

get_latest_version() {
  local type="$1" version

  local json_file="$TEMP_DIR/${type}_response.json"

  # 检查文件是否存在
  if [ ! -f "$json_file" ]; then
    log ERROR "❌ JSON 文件不存在：$json_file" >&2
    return 1
  fi

  # 先验证 JSON 是否为数组，避免用 .[] 出错
  if ! jq -e 'type == "array"' "$json_file" >/dev/null; then
    log ERROR "❌ JSON 格式错误，预期为数组，请检查网络情况或请求次数达到限制：$json_file" >&2
    return 1
  fi

  # 安全提取 tag_name 字段并筛选
  version=$(jq -r '.[].tag_name' "$json_file" 2>/dev/null |
    grep -vE "rc|beta|dict-nightly" |
    sort -Vr |
    head -n 1)

  # 如果提取为空
  if [ -z "$version" ]; then
    log ERROR "❌ 没有找到有效的 tag_name 版本" >&2
    return 1
  fi

  echo "$version"
}
# 脚本自检
update_tools_check() {
  if [[ "$UPDATE_TOOLS_VERSION" =~ ^"DEFAULT" ]]; then
    log WARN "你正在使用源文件！"
    log WARN "请从 $GH_DL/$UPDATE_TOOLS_REPO/releases/latest 页面下载正式版！"
    error_exit "操作终止"
  fi
  log INFO "工具当前版本 $UPDATE_TOOLS_VERSION"
  log INFO "正在检查本工具是否有更新"
  local local_version remote_version
  get_github_response "tools"
  local_version="$UPDATE_TOOLS_VERSION"
  remote_version=$(get_latest_version "tools")
  if [[ "$remote_version" > "$local_version" ]]; then
    log WARN "检测到工具最新版本为: $remote_version, 建议更新后继续"
    log WARN "你可从该链接下载: $GH_DL/$UPDATE_TOOLS_REPO/releases/tag/$remote_version"
  else
    log INFO "工具已是最新版本"
  fi
}
# 首次使用配置
first_config() {
  log INFO "您似乎是第一次使用该工具，接下来引导您进行必要的配置"
  local schema_type help_code
  schema_type=("base" "pro")
  help_code=("flypy" "hanxin" "jdh" "moqi" "tiger" "wubi" "zrm")
  local input schema helpcode confirm
  input=$ENGINE
  log INFO "请选择您使用方案类型"
  PS3="请输入选项前数字: "
  select _choice in "${schema_type[@]}"; do
    [[ -n "$_choice" ]] || error_exit "无效的选择"
    schema="$_choice"
    break
  done
  if [[ "$schema" == "pro" ]]; then
    log INFO "请选择您使用的辅助码"
    PS3="请输入选项前数字: "
    select _choice in "${help_code[@]}"; do
      [[ -n "$_choice" ]] || error_exit "无效的选择"
      helpcode="$_choice"
      break
    done
  else
    helpcode="base"
  fi
  log INFO "您选择了以下方案组合: "
  log INFO "输入引擎: $input"
  log INFO "方案类型: $schema"
  [[ "$schema" == "base" ]] || log INFO "辅助码  : $helpcode"
  log INFO "部署目录: $DEPLOY_DIR"
  log INFO "这些内容是否正确？"
  read -rp "请输入 YES 或 NO (区分大小写): " confirm
  [[ "$confirm" == "YES" ]] || error_exit "用户终止操作"
  mkdir -p "$TOOLS_DIR" || error_exit "你没有部署目录的访问权限！"
  mkdir -p "$RAW_DIR" || error_exit "你没有部署目录的访问权限！"
  echo -e "{
  \"input\": \"$input\",\n  \"schema\": \"${schema}\",
  \"helpcode\": \"$helpcode\",\n  \"deploy_dir\": \"$DEPLOY_DIR\",
  \"exclude_file\": []\n}" >"$CONFIG_FILE"
  echo -e "{
  \"version\": \"null\",
  \"schema\": {\n    \"name\": \"null\",\n    \"sha256\": \"null\",
    \"update\": \"1970-01-01T00:00:00Z\",\n    \"url\": \"null\"\n  },
  \"dict\": {\n    \"name\": \"null\",\n    \"sha256\": \"null\",
    \"update\": \"1970-01-01T00:00:00Z\",\n    \"url\": \"null\"\n  },
  \"gram\": {\n    \"name\": \"null\",\n    \"sha256\": \"null\",
    \"update\": \"1970-01-01T00:00:00Z\",\n    \"url\": \"null\"\n  }\n}" >"$UPDATE_FILE"
  add_exclude_file
}
add_exclude_file() {
  log INFO "接下来将添加更新时需要保留的内容"
  log INFO "请输入需要保留的文件/目录的相对路径"
  log INFO "例如你想要保留部署目录下的 \"wanxiang.custom.yaml\""
  log INFO "该文件完整路径为: $DEPLOY_DIR/wanxiang.custom.yaml"
  log INFO "那么你只需要输入 \"wanxiang.custom.yaml\" 即可"
  log INFO "每次只可以输入一个文件或目录"
  log INFO "我们已经预设了以下内容作为排除项"
  log INFO "\"installation.yaml\" \"user.yaml\""
  log INFO "\"*.custom.yaml\" \"*.userdb\""
  log INFO "全部输入完成后，请输入 \"DONE\" 来结束 (区分大小写)"
  log WARN "请仔细阅读以上内容" && sleep 3
  local newdata newjson
  EXCLUDE_FILE=(
    "update_tools_config"
    "installation.yaml"
    "user.yaml"
    ".custom.yaml"
    ".userdb"
  )
  for _newdata in "${EXCLUDE_FILE[@]}"; do
    newjson=$(jq --arg newdata "$_newdata" '.exclude_file += [$newdata]' "$CONFIG_FILE")
    echo "$newjson" >"$CONFIG_FILE"
  done
  while true; do
    read -rp "请输入需要排除的内容 (输入 DONE 结束): " newdata
    [[ "$newdata" != "DONE" ]] || break
    if [[ -n $newdata ]]; then
      newjson=$(jq --arg newdata "$newdata" '.exclude_file += [$newdata]' "$CONFIG_FILE")
      echo "$newjson" >"$CONFIG_FILE"
      log INFO "已添加 $DEPLOY_DIR/$newdata 到保留内容"
    fi
  done
  log INFO "以下内容为更新时保留内容，这些内容是否正确？"
  jq '.exclude_file[]' "$CONFIG_FILE"
  read -rp "请输入 YES 或 NO (区分大小写): " confirm
  if [[ "$confirm" != "YES" ]]; then
    rm -rf "$TOOLS_DIR"
    error_exit "用户终止操作"
  fi
}
new_update_info() {
  local version="$1" helpcode="$2" type="$3" newfile="$4" newdata newjson
  newdata=$(jq -r --arg version "$version" --arg help_code "$helpcode" \
    '.[] | select(.tag_name == $version ) | 
    .assets.[]| select(.name | test($help_code)) |
    { name: .name, sha256: .digest, update: .updated_at, url: .browser_download_url }' \
    "$TEMP_DIR/${type}_response.json")
  newjson=$(jq --arg type "$type" --argjson newdata "$newdata" '.[$type] = $newdata' "$newfile")
  echo "$newjson" >"$newfile"
}
check_update() {
  local helpcode="$1" newfile="$2" deploy_dir="$3"
  local local_data remote_data
  local schemacheck dictcheck gramcheck
  # 方案文件
  local_data=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$(jq -r '.schema.update' "$UPDATE_FILE")" "+%s")
  remote_data=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$(jq -r '.schema.update' "$newfile")" "+%s")
  if [[ ! $local_data < $remote_data ]]; then
    log INFO "方案文件 无需更新"
    schemacheck="NO"
  else
    download_and_unzip "schema" "$newfile"
    schemacheck="YES"
  fi
  # 词典文件
  local_data=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$(jq -r '.dict.update' "$UPDATE_FILE")" "+%s")
  remote_data=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$(jq -r '.dict.update' "$newfile")" "+%s")
  if [[ ! $local_data < $remote_data ]]; then
    log INFO "词典文件 无需更新"
    dictcheck="NO"
  else
    download_and_unzip "dict" "$newfile"
    dictcheck="YES"
  fi
  # 语法模型
  local_data=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$(jq -r '.gram.update' "$UPDATE_FILE")" "+%s")
  remote_data=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$(jq -r '.gram.update' "$newfile")" "+%s")
  if [[ ! $local_data < $remote_data ]]; then
    log INFO "语法模型 无需更新"
    gramcheck="NO"
  else
    download_and_unzip "gram" "$newfile"
    gramcheck="YES"
  fi
  [[ "$schemacheck" == "NO" && "$dictcheck" == "NO" && "$gramcheck" == "NO" ]] ||
    touch "$TEMP_DIR/needed_update"
}
download_and_unzip() {
  local type="$1" newfile="$2" displayname
  case "$type" in
  schema) displayname="方案文件" ;;
  dict) displayname="词典文件" ;;
  gram) displayname="语法模型" ;;
  esac
  log INFO "$displayname 需要更新，正在下载最新文件"
  mkdir -p "$RAW_DIR"
  local filename filehash fileurl checkhash
  filename=$(jq -r --arg type "$type" '.[$type].name' "$newfile")
  filehash=$(jq -r --arg type "$type" '.[$type].sha256' "$newfile" | awk -F ':' '{print $2}')
  fileurl=$(jq -r --arg type "$type" '.[$type].url' "$newfile")
  if [[ -f "$RAW_DIR/$filename" ]]; then
    checkhash=$(sha256sum "$RAW_DIR/$filename" | awk '{print $1}')
    if [[ "$filehash" != "$checkhash" ]]; then
      rm -r "$RAW_DIR/${filename:?}"
      curl -L --connect-timeout 5 -o "$RAW_DIR/$filename" "$fileurl"
      checkhash=$(sha256sum "$RAW_DIR/$filename" | awk '{print $1}')
      [[ "$filehash" == "$checkhash" ]] || error_exit "文件下载出错，请重试！"
    else
      log INFO "文件已存在，跳过下载"
    fi
  else
    curl -L --connect-timeout 5 -o "$RAW_DIR/$filename" "$fileurl"
    checkhash=$(sha256sum "$RAW_DIR/$filename" | awk '{print $1}')
    [[ "$filehash" == "$checkhash" ]] || error_exit "文件下载出错，请重试！"
  fi
  if [[ "$type" == "schema" ]]; then
    unzip -q "$RAW_DIR/$filename" -d "$TEMP_DIR/$type"
  elif [[ "$type" == "dict" ]]; then
    unzip -q "$RAW_DIR/$filename" -d "$TEMP_DIR"
    mv "$TEMP_DIR"/*dicts "$TEMP_DIR/$type"
  fi
}
update_all_file() {
  local deploy_dir="$1"
  if [[ -d "$TEMP_DIR/schema" ]]; then
    log INFO "正在更新 方案文件"
    rm -rf "$TEMP_DIR/schema"/{简纯+.trime.yaml,custom_phrase.txt,squirrel.yaml,weasel.yaml}
    find "$TEMP_DIR/schema" -type f -exec chmod 644 {} +
    EXCLUDE_FILE=()
    while IFS= read -r line; do
      EXCLUDE_FILE+=("$line")
    done < <(jq -r '.exclude_file[]' "$CONFIG_FILE")

    for _file in "${EXCLUDE_FILE[@]}"; do
      cp -rf "$deploy_dir"/*"$_file" "$TEMP_DIR/schema"
    done
    rm -rf "$deploy_dir"
    cp -rf "$TEMP_DIR/schema" "$deploy_dir"
  fi
  if [[ -d "$TEMP_DIR/dict" ]]; then
    log INFO "正在更新 词典文件"
    cp -rf "$TEMP_DIR/dict"/* "$deploy_dir/zh_dicts"*/
  fi
  log INFO "正在更新 语法模型"
  cp -rf "$RAW_DIR"/*.gram "$deploy_dir"
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

# 主函数
main() {
  trap cleanup EXIT
  # 检查必要的依赖
  check_deps
  # 检查临时目录
  [[ -d "$TEMP_DIR" ]] || error_exit "临时目录创建失败"
  # 欢迎语
  log INFO "欢迎使用 Rime 万象输入方案 更新助手"
  # 脚本自检
  update_tools_check
  # 判断是否第一次使用
  [[ -d "$TOOLS_DIR" ]] || first_config
  # 获取用户设置
  local helpcode deploy_dir
  helpcode=$(jq -r '.helpcode' "$CONFIG_FILE")
  deploy_dir=$(jq -r '.deploy_dir' "$CONFIG_FILE")
  # 缓存 GitHub API 响应
  get_github_response "schema"
  get_github_response "dict"
  get_github_response "gram"
  # 检查版本号
  local local_data remote_data
  local_data=$(jq -r '.version' "$UPDATE_FILE")
  remote_data=$(get_latest_version "schema")
  log INFO "当前版本号为 $local_data, 最新版本号为 $remote_data"
  [[ ! "$local_data" > "$remote_data" ]] || log INFO "正在检查是否需要更新"
  # 生成新版 update_info
  local newfile newjson
  cp "$UPDATE_FILE" "$TEMP_DIR/new_update_info.json"
  newfile="$TEMP_DIR/new_update_info.json"
  newjson=$(jq --arg newdata "$remote_data" '.version = $newdata' "$newfile")
  echo "$newjson" >"$newfile"
  new_update_info "$remote_data" "$helpcode" "schema" "$newfile"
  new_update_info "dict-nightly" "$helpcode" "dict" "$newfile"
  new_update_info "LTS" "lts" "gram" "$newfile"
  # 检查更新
  check_update "$helpcode" "$newfile" "$deploy_dir"
  if [[ -f "$TEMP_DIR/needed_update" ]]; then
    log INFO "开始更新文件"
    update_all_file "$deploy_dir"
    mv "$newfile" "$UPDATE_FILE"
    log INFO "更新完成！"
    # 自动部署
    if [ "$ENGINE" = "squirrel" ]; then
      DEPLOY_EXECUTABLE="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
      deploy "$DEPLOY_EXECUTABLE" --reload
    else
      DEPLOY_EXECUTABLE="/Library/Input Methods/Fcitx5.app/Contents/bin/fcitx5-curl"
      deploy "$DEPLOY_EXECUTABLE" /config/addon/rime/deploy -X POST -d '{}'
    fi
  else
    log INFO "你正在使用最新版本，无需更新"
  fi
}
# 调用主函数
main
