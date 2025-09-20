# 安卓更新

## 依赖说明

- **需要 Termux , 且启用了存储权限**
- Termux 中需要安装 Python
- 安装 requests 库

```bash
pkg install python
pip install requests
pip install tqdm
```

## 逻辑说明

安卓检测脚本同级目录下的 Rime或rime 子文件夹，没有就创建 Rime 子文件夹.

## 前端适配

- [小企鹅输入法导入包构建脚本](Fcitx5-For-Android/README.md)
  - 使用更新工具更新完之后，使用小企鹅打包工具将 Rime 文件夹打包成小企鹅备份文件，直接导入即可。
- [同文输入法更新说明](trime/README.md)
  - 同文输入法设置对应的用户文件夹即可直接部署使用。
