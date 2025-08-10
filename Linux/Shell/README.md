# Rime 万象方案方案更新 - Linux Shell 脚本

## 简介

这是一个用于更新 Rime 输入法方案的 Linux Shell 脚本。该脚本可以帮助用户自动从 GitHub 上下载最新的方案文件，并将其部署到指定的目录中。

## 环境要求

- `curl` 程序
- `unzip` 程序
- `jq` 程序

## 使用教程

### 为脚本添加可执行权限

```bash
chmod +x rime-wanxiang-update-linux
```

### 设置部署目录

使用任意编辑器打开脚本文件，修改 `DEPLOY_DIR=""` 为你需要的内容  
比如 `DEPLOY_DIR="$HOME/.local/share/fcitx5/rime"`

### 创建排除列表文件

在部署目录下创建名为 `user_exclude_file.txt` 的文件，以下是一个示例

- 注释内容以 "#" 开头

```txt
# 文件本身
user_exclude_file.txt
# 用户数据库
lua/sequence.userdb
user_flypyzc.userdb
# custom 文件
default.custom.yaml
wanxiang_pro.custom.yaml
wanxiang_reverse.custom.yaml
wanxiang_mixedcode.custom.yaml
# 萌娘百科词库
dicts/moegirl.pro.dict.yaml
wanxiang_pro.dict.yaml
# 自定义 lua
lua/shijian.lua
lua/super_comment.lua
```

### 使用适当的参数运行脚本

以下内容使用专业版、自然码辅助码进行示例，请按需修改  
你可以组合多个参数运行

#### 使用 CNB 镜像

```bash
rime-wanxiang-update-linux --mirror cnb
```

#### 更新全部内容

```bash
rime-wanxiang-update-linux --schema pro --fuzhu zrm --dict --gram
```

#### 只更新方案文件

```bash
rime-wanxiang-update-linux --schema pro --fuzhu zrm
```

#### 只更新词典文件

```bash
rime-wanxiang-update-linux --dict --fuzhu zrm
```

#### 只更新语法模型

```bash
rime-wanxiang-update-linux --gram
```

### 高级用法

#### 传入 DEPLOY_DIR 与 inputime

脚本还支持直接传入部署目录，这样可以避免修改脚本，方便更新脚本自身  
以下是一个示例

```bash
rime-wanxiang-update-linux --depdir "$HOME/.local/share/fcitx5/rime"
```

脚本也可以传入输入引擎，这可以实现 Rime 的自动部署  
以下是一个示例

```bash
rime-wanxiang-update-linux --inputime fcitx5
```
