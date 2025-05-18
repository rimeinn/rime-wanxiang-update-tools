# Rime 万象方案方案更新 - Linux Bash 脚本

## 简介

这是一个用于更新 Rime 输入法方案的 Linux Bash 脚本。该脚本可以帮助用户自动从 GitHub 上下载最新的方案文件，并将其部署到指定的目录中。

## 环境要求

- Linux 系统
- Bash 环境
- wget 命令
- unzip 命令
- md5sum 命令

## 使用方法

1. 确保脚本具有执行权限 ：

```bash
chmod +x wanxiang-update
```

2. 运行脚本 ：

```bash
./wanxiang-update
```

3. 按照提示输入信息 ：
   - 方案名 ：输入要更新的方案名，例如 zrm 。可用的方案包括 moqi 、 flypy 、 zrm 、 jdh 、 cj 、 tiger 、 wubi 和 hanxin 。
   - 版本号 ：输入要下载的方案版本号，例如 6.8 。
   - 部署目录 ：输入文件的部署目录，默认为 `$HOME/.local/share/fcitx5/rime` 。

## 脚本功能

### 方案更新 (update_schema)

从 GitHub 下载指定版本的方案文件，解压后删除无用文件，然后将更新后的文件复制到部署目录。

### 词典更新 (update_dicts)

从 GitHub 下载指定方案的词典文件，解压后将更新后的词典文件复制到部署目录的 cn_dicts 文件夹。

### 语法模型更新 (update_gram)

比较本地语法模型文件的 MD5 值和远程文件的 MD5 值，如果不一致则下载最新的语法模型文件并替换本地文件。

### 自定义文件排除（usercustom.txt）

在更新过程中，脚本会检查是否存在 usercustom.txt 文件。如果存在，脚本会读取该文件中的内容，将其中的文件和文件夹排除在更新之外。每行一个。

## 注意事项

- 脚本需要一个 **usercustom.txt** 文件，该文件位于部署目录下，用于指定更新时需要保留的文件和文件夹。如果该文件不存在，脚本将输出错误信息并退出。
- 请确保你的网络连接正常，否则可能会导致文件下载失败。
- 更新完成后，请重新部署 Rime 输入法方案以使更改生效。
