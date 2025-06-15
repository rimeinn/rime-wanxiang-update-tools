# trime 同文输入法

## 更新方式

1. 将更新 python 全平台更新脚本放到你想放置的文件夹中 `例如 document/Github/trime`(手机文件夹管理视角)
2. 这个时候更新脚本的路径为 `Document/Github/trime/rime-wanxiang-update-win-mac-ios-android.py`(手机文件夹管理视角)
3. 运行脚本
   1. 打开 Termux
   2. cd 到对应的脚本存放路径 ~/storage/document/Github/trime (Termux 视角)
   3. 运行脚本

```python
python rime-wanxiang-update-win-mac-ios-android.py
```

## 逻辑说明

安卓检测脚本同级目录下的 Rime/rime 子文件夹，没有就创建 Rime 子文件夹.

## 设置同文输入法

设置同文输入法中的 "配置->用户文件夹" 为 `document/Github/trime/Rime` **即与更新脚本同级目录下的 Rime 子目录**
