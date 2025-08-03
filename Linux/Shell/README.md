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

- 注意：这是一个 `txt` 文件，请不要写注释等无关内容

```txt
user_exclude_file.txt
user_zrm.userdb
user_zrmzc.userdb
lua/tips/tips_user.txt
default.custom.yaml
wanxiang_mixedcode.custom.yaml
wanxiang_pro.custom.yaml
wanxiang_reverse.custom.yaml
```

第一行：该文件本身，千万不要忘了它  
第二行—第三行：文件夹示例  
第四行：子目录文件示例  
第五行—第八行：custom 文件示例

### 使用适当的参数运行脚本

以下内容使用专业版、自然码辅助码进行示例，请按需修改  
你可以组合多个参数运行

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

#### 更新方案文件与词典文件

```bash
rime-wanxiang-update-linux --schema pro --fuzhu zrm --dict
```

#### 更新方案文件与语法模型

```bash
rime-wanxiang-update-linux --schema pro --fuzhu zrm --gram
```

#### 更新词典文件与语法模型

```bash
rime-wanxiang-update-linux --fuzhu zrm --dict --gram
```
