# Win-Mac-iOS融合版

**合并Windows、Mac、iOS端的Python脚本，支持万象基础版和Pro版**

- 下载链接：[rime-wanxiang-update-win-mac-ios-android.py](https://github.com/rimeinn/rime-wanxiang-update-tools/releases/latest/download/rime-wanxiang-update-win-mac-ios-android.py)

## 使用须知

开启自动更新时，支持`-s`或`--script`参数选择更新脚本本身，未提供参数则默认只检测脚本是否有更新：
```shell
python rime-wanxiang-update-all.py -s
```

**仅在开启自动更新时有效**

## 注意事项

- 如果脚本有更新，请更新脚本后，重新打开脚本确保成功覆盖以后再运行（如：iOS端需退出Pythonista 3重新打开）
- 在Windows下运行，如遇到乱码问题（如下图），可在微软商店下载Windows Terminal Preview，或是通过命令行启用虚拟终端
    ![屏幕截图 2025-06-23 202131](https://github.com/user-attachments/assets/ee4a9c86-e76e-4433-9114-9b31088fb677)
    ![屏幕截图 2025-06-23 202028](https://github.com/user-attachments/assets/6b582f17-7819-44bb-aefb-bd239b876cc7)
- **启用虚拟终端**：

  ```cmd
  reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f
  ```

- **禁用虚拟终端**：

  ```cmd
  reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 0 /f
  ```
