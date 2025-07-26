# Rime 万象方案方案更新 - Mac端 Shell 脚本

## 简介

这是一个用于更新 Rime 输入法方案的 Mac Shell 脚本。该脚本可以帮助用户自动从 GitHub 上下载最新的方案文件，并将其部署到指定的目录中。

## 环境要求

- `curl` 命令
- `unzip` 命令

## 使用教程

1. 为脚本添加可执行权限

```bash
chmod +x wanxiang-update
```

2. 在脚本中 `ENGINE=""`的双引号中填入你所使用的引擎：小企鹅为 `fcitx5`，鼠须管为 `squirrel`

3. 在 `EXCLUDE_FILE=()` 数组中加入你需要排除的文件，不建议修改预设。

4. 运行脚本，按照提示输入。

```bash
./wanxiang-update
```

> 可以在系统环境变量中添加GitHub Token以避免请求限制，应设置变量名为`GITHUB_TOKEN`
