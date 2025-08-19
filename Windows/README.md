# Rime 万象更新工具 - Windows 版本 - 只支持小狼毫前端

## 项目简介

本工具用于在Windows系统上自动更新Rime输入法的万象方案、词库和模型。

## 版本列表

- [PowerShell版本](./PowerShell/README.md)

## 使用说明

1. 选择对应的版本
2. 按照说明文档进行操作
3. 工具将自动完成更新

## 常见问题解决方案

当你在使用最新的版本的脚本时（默认使用 cnb 源），可能会在更新方案文件的时候出现 `解压失败: 使用“1”个参数调用“.ctor”时发生异常:“路径中具有非法字符。”` 问题，这个是因为你使用的 PowerShell 5 版本，可以通过升级到 PowerShell 7 解决，同时升级到 PowerShell 7 后，如果出现输入提示乱码，请下载 utf-8 后缀版本的更新脚本。使用 GitHub 源无此影响。

升级链接：https://learn.microsoft.com/zh-cn/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7?view=powershell-7.5#installing-powershell-7

## 许可证

MIT License
