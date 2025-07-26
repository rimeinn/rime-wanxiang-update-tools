# Rime 万象更新工具-Windows 版本(只适用于小狼毫前端)

## 简介

本工具用于自动下载和更新 Rime 输入法的[万象方案、词库和语言模型](https://github.com/amzxyz/rime_wanxiang_pro)。支持多种输入方案，包括仓颉、小鹤、汉心、简单鹤、墨奇、虎码、五笔和自然码。

## 功能

- 自动检测最新版本
- 按需下载方案、词库和模型
- 自动解压和安装
- 记录更新时间，避免重复下载
- 支持通过GitHub API获取最新版本信息
- 自动重启Rime输入法服务

## 使用说明

1. 确保已安装 Rime 输入法（小狼毫）
   - **本工具仅支持小狼毫前端**，其他Rime前端可能无法正常使用
2. 运行脚本 `按需下载万象方案-词库-模型.ps1`
3. 根据提示选择要下载的内容：
   - 输入方案类型编号（0-7）
   - 选择是否更新所有内容[0/1]
     0. 表示更新方案、词库、模型
     1. 手动选择是否下载方案、词库和模型
4. 等待下载和安装完成

## 脚本运行效果展示

```powershell
E:\Github\rime-wanxiang-update-tools\按需下载万象方案-词库-模型.ps1
Weasel用户目录路径为: E:\Github\wanxiang-zrm-fuzhu
解析出最新的词库链接为：https://github.com/amzxyz/rime_wanxiang_pro/releases/tag/dict-nightly
解析出最新的版本链接为：https://github.com/amzxyz/rime_wanxiang_pro/releases/tag/v6.7.9
解析出最新的模型链接为：https://github.com/amzxyz/RIME-LMDG/releases/tag/LTS
最新的版本为：v6.7.9
请选择你要下载的辅助码方案类型的编号:
[0]-仓颉; [1]-小鹤; [2]-汉心; [3]-简单鹤; [4]-墨奇; [5]-虎码; [6]-五笔; [7]-自然码: 7
是否更新所有内容（方案、词库、模型）:
[0]-更新所有; [1]-不更新所有: 0
下载方案
下载词库
下载模型
正在更新词库，请不要操作键盘，直到更新完成
更新完成后会自动拉起小狼毫
正在检查方案是否需要更新...
本地时间: 05/15/2025 21:16:24
远程时间: 05/15/2025 21:16:24
当前已是最新版本
正在检查词库是否需要更新...
本地时间: 05/16/2025 14:54:23
远程时间: 05/16/2025 14:54:23
当前已是最新版本
正在检查模型是否需要更新...
本地时间: 05/12/2025 14:03:36
远程时间: 05/12/2025 14:03:36
当前已是最新版本
操作已完成！文件已部署到 Weasel 配置目录:E:\Github\wanxiang-zrm-fuzhu
```

## 注意事项

- 更新过程中请勿操作键盘
- 更新完成后会自动重启 Rime 输入法
- 建议定期运行本工具以保持输入法最新
- 需要Windows PowerShell 5.1或更高版本
- 需要稳定的网络连接

## 依赖

- PowerShell 5.1 或更高版本
- 网络连接
- GitHub API访问权限
- [Rime wanxiang pro](https://github.com/amzxyz/rime_wanxiang_pro)

## 许可证

MIT License
