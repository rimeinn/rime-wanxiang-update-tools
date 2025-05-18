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
WANXIANG=""
SCHEMA=""
DEPLOYDIR=""
```

参照脚本注释设置文件开头这三个变量，即可自动化整个更新过程。

## 注意事项

- 你需要一个良好的网络连接。
- 脚本会在部署目录生成 `updatetime.txt` 文件，请不要修改。
- 第一次运行脚本会出现 `awk：致命错误` 字样，这是预期的，无需干预。