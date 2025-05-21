# Rime 万象更新工具 - Python 版本

## 简介

本工具是为iOS上的Rime输入法（Hamster输入法）用户设计的自动更新工具，使用Python编写，需要在Pythonista 3上执行。

## 功能特性

- 自动检测最新版本的Rime方案、词库和模型
- 按需下载更新文件，避免重复下载
- 自动解压和安装更新文件
- 记录更新时间，便于管理
- 支持GitHub API获取最新版本信息
- 自动重启Rime输入法服务
- 提供友好的命令行交互界面

## 使用要求

- [Pythonista 3](https://apps.apple.com/us/app/pythonista-3/id1085978097)
- [Hamster](https://apps.apple.com/us/app/%E4%BB%93%E8%BE%93%E5%85%A5%E6%B3%95/id6446617683)


## 安装步骤

1. 确保已安装上面两个app
2. 下载本工具到Hamster输入法目录
3. 在Pythonista 3中打开脚本并运行


## 使用说明

1. 首次运行时会自动检测系统配置
2. 根据提示选择需要使用的输入法方案
3. 程序会自动完成更新过程
4. 更新完成后需手动重新部署

## 注意事项

- 更新过程中请勿操作键盘
- 确保网络连接稳定
- 建议定期运行本工具以保持输入法最新
- 如果遇到问题，请检查系统路径配置
- 更改配置请直接在Pythonista 3中打开`Settings.ini`进行修改

## 贡献

欢迎提交issue或pull request

## 许可证

MIT License
