# Rime 万象更新工具 - iOS 版本 - 需下载Hamster输入法和Pythonista 3或a-shell或pyto或Code App

[Hamster](https://apps.apple.com/us/app/%E4%BB%93%E8%BE%93%E5%85%A5%E6%B3%95/id6446617683)

[Pythonista 3](https://apps.apple.com/us/app/pythonista-3/id1085978097) / [a-shell](https://apps.apple.com/us/app/a-shell/id1473805438) / [pyto](https://apps.apple.com/us/app/pyto-ide/id1436650069) / [Code App](https://apps.apple.com/us/app/code-app/id1512938504)

**推荐使用[a-shell](https://apps.apple.com/us/app/a-shell/id1473805438)，免费**

## 项目简介

本工具用于在iOS系统上自动更新Rime输入法（Hamster）的万象方案、词库和模型。

## 版本列表

- [Python版本](../Python-全平台版本/README.md)
- [Shortcuts版本](./Shortcuts/README.md)

## 使用说明

### Python版本

1. 将脚本放在Hamster输入法路径下
2. 运行脚本，选择对应的版本
3. 按照说明文档进行操作
4. 工具将自动完成更新
5. 更新完成后需手动打开Hamster输入法重新部署

**注意：**
若使用[a-shell](https://apps.apple.com/us/app/a-shell/id1473805438)，则打开a-shell后，先下载所需包

```shell
pip install requests tqdm
```

然后输入`pickFolder`，选择Hamster输入法的文件夹（也是脚本所在的文件夹），运行：

```shell
python rime-wanxiang-update-win-mac-ios-android.py
```

为方便使用，也可以进行如下操作：

1. 打开`.bashrc`文件：

    ```shell
    cd ~
    vim .bashrc
    ```

2. 插入如下内容（按`i`进入插入模式）

    ```shell
    alias rime='python rime-wanxiang-update-win-mac-ios-android.py'
    ```

3. 按`esc`，然后输入`:wq`，回车保存，执行`source .bashrc`
4. 使用`pickFolder`重新打开Hamster文件夹
5. 执行`rime`命令即可运行脚本

### Shortcuts版本

1. 获取两个快捷指令 [万象方案下载(支持CNB和GitHub)](https://www.icloud.com/shortcuts/609c5cbeca0148baaf430d43927a957a) 和 [日常自动更新万象中文词库](https://www.icloud.com/shortcuts/bd6eee4c48ee4f669bf24f83157f4d4e)
2. 打开并根据提示配置
3. 执行一次获取权限
4. `日常自动更新万象中文词库`可以添加到自动化设置时间进行执行，`万象Pro版本下载`可以根据需要手动执行

## 许可证

MIT License
