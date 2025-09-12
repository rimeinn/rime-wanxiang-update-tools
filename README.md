# Rime 万象更新工具

## 项目简介

本工具用于自动更新Rime输入法的万象方案、词库和模型，支持Windows、macOS和Linux系统。

## 工具版本计划

- [x] [Windows版本](./Windows/README.md)
- [x] [macOS版本](./Mac/README.md)
- [x] [Linux版本](./Linux/README.md)
- [x] [iOS版本](./iOS/README.md)
- [x] [Android版本(同文、小企鹅导入包通用构建脚本)](./Android/README.MD)

### Python-全平台版本

- [x] [Python版本](./Python-全平台版本/README.md)
  - 下载链接：[rime-wanxiang-update-win-mac-ios-android.py](https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/rime-wanxiang-update-win-mac-ios-android.py)

### Windows版本

- **版本区别**
  - **执行环境**: PowerShell 运行环境 Windows 10 自带，Python 需要自己安装 Python 环境
  - **运行方式**: PowerShell版本直接双击运行；Python版本需要命令行执行
  - **功能实现**: 两个版本功能相同，但Python版本更易于跨平台移植
    - Python 版本支持从 CNB （直连）仓库下载

- [x] [PowerShell版本](./Windows/PowerShell/README.md)
  - 下载链接：[按需下载万象方案-词库-模型(GBK版本：文件名：**rime-wanxiang-update-windows.ps1**)](https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/rime-wanxiang-update-windows.ps1)
  - 下载链接：[按需下载万象方案-词库-模型(UTF-8版本：文件名：**rime-wanxiang-update-windows-utf-8.ps1**](https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/rime-wanxiang-update-windows-utf-8.ps1)
- [x] [Python版本](./Python-全平台版本/README.md)
  - 下载链接：[rime-wanxiang-update-win-mac-ios-android.py](https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/rime-wanxiang-update-win-mac-ios-android.py)

### Linux版本

- [x] [Shell版本](./Linux/Shell/README.md)
  - 下载链接：[Linux/Shell/wanxiang-update](https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/linux-wanxiang-update)

### Mac版本

- [x] [Python版本](./Python-全平台版本/README.md)
  - 下载链接：[rime-wanxiang-update-win-mac-ios-android.py](https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/rime-wanxiang-update-win-mac-ios-android.py)
- [x] [Shell版本](./Mac/Shell/README.md)
  - 下载链接：[rime-wanxiang-update-macos.sh](https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/rime-wanxiang-update-macos.sh)

### iOS版本

- [x] [Python版本](./Python-全平台版本/README.md)
  - 下载链接：[rime-wanxiang-update-win-mac-ios-android.py](https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/rime-wanxiang-update-win-mac-ios-android.py)
- [x] [Shortcuts版本](./iOS/Shortcuts/README.md)

## 使用说明

1. 选择对应的系统版本
2. 按照说明文档进行操作
3. 工具将自动完成更新

### Windows 下 PowerShell 脚本运行方式

Windows 默认不支持无签名的 ps 脚本运行，如果右键运行失败，请在终端中运行。如果提示如下错误：

```PowerShell
C:\Users\xxx\Desktop\按需下载万象方案-词库-模型.ps1，因为在此系统上禁止运行脚本。
```

请参考以下两种方式运行：

#### 方式一（推荐，安全）：临时放行执行策略

无需修改全局策略，直接用 PowerShell 7（pwsh）临时放行：

```powershell
pwsh -ExecutionPolicy Bypass -File .\Windows\PowerShell\按需下载万象方案-词库-模型-utf-8.ps1
```

如需更便捷体验，可新建一个 `run-update.bat` 启动器，内容如下：如果出现编码错误（即打印乱码的话，你需要调整下载链接使用 utf-8 版本）

```bat
@echo off
set SCRIPT=按需下载万象方案-词库-模型.ps1
set URL="https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/rime-wanxiang-update-windows.ps1"

if not exist "%SCRIPT%" (
  echo 未找到 %SCRIPT%，正在下载...
  powershell -Command "Invoke-WebRequest -Uri '%URL%' -OutFile '%SCRIPT%'"
  if errorlevel 1 (
    echo 下载失败，请检查网络连接。
    pause
    exit /b 1
  )
)

echo 正在运行脚本...
pwsh -ExecutionPolicy Bypass -File "%SCRIPT%"
pause
```

#### 方式二（便捷但有风险）：修改执行策略

可用如下命令放宽当前用户的执行策略（有一定安全风险，不推荐）：

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser
```

然后直接运行脚本：

```powershell
powershell -File .\Windows\PowerShell\按需下载万象方案-词库-模型-utf-8.ps1
```

> ⚠️ 注意：修改执行策略有一定安全风险，建议用完后恢复默认：
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy Restricted -Scope CurrentUser
> ```

```PowerShell
C:\Users\12418\Desktop\按需下载万象方案-词库-模型.ps1，因为在此系统上禁止运行脚本。有关详细信息，请参阅 https:/go.microsoft.com/fwlink/?LinkID=135170 中的 about_Executio
n_Policies。
所在位置 行:1 字符: 1
+ C:\Users\12418\Desktop\按需下载万象方案-词库-模型.ps1
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : SecurityError: (:) []，PSSecurityException
    + FullyQualifiedErrorId : UnauthorizedAccess
```

请在终端中运行以下命令，然后再运行脚本即可。

```PowerShell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser
```

## 许可证

MIT License
