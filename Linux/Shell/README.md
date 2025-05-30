# Rime 万象方案方案更新 - Linux Shell 脚本

## 简介

这是一个用于更新 Rime 输入法方案的 Linux Shell 脚本。该脚本可以帮助用户自动从 GitHub 上下载最新的方案文件，并将其部署到指定的目录中。

## 环境要求

- `curl` 命令
- `unzip` 命令

## 使用教程

1. 为脚本添加可执行权限

```bash
chmod +x wanxiang-update
```

2. 在 `EXCLUDE_FILE=()` 数组中加入你需要排除的文件，不建议修改预设。

3. 运行脚本，按照提示输入。

```bash
./wanxiang-update
```

## 自动化配置（无人值守更新）

```bash
# 输入框架, 可选 "Fcitx5" "iBus"
# 例如: INPUT_TYPE="Fcitx5"
INPUT_TYPE=""
# 方案类型, 可选 "base" "pro"
# 例如: SCHEME_TYPE="pro"
SCHEME_TYPE=""
# 辅助码类型, 基础版请填 "base"
# 专业版可选 "cj" "flypy" "hanxin" "jdh" "moqi" "tiger" "wubi" "zrm"
# 例如: HELP_CODE="zrm"
HELP_CODE=""
# 部署目录, 填入你需要部署的目录
# 例如:
# DEPLOY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/rime" # Fcitx5 默认路径
# DEPLOY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ibus/rime" # iBus 默认路径
DEPLOY_DIR=""
# 用户确认选项, 自动化填 Yes 即可, 可选 "Yes" "No"
# 例如: IS_TRUE="Yes"
IS_TRUE=""
# 更新时需要保留的文件
# 例如: EXCLUDE_FILE=(
#   "这是一个目录"
#   "这是一个文件"
#   "......"
# )
EXCLUDE_FILE=()
```

参照脚本注释设置文件开头这些变量，即可自动化整个更新过程。
