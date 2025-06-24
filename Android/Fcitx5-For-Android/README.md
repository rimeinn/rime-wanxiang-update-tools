# Fcitx5 for Android 方案导入包生成工具

## 使用场景

- 适用场景：想把已经配置好的 Rime 方案迁移到到 f5a 中使用，但是普通方法操作过于繁琐
- 功能说明：根据指示指定需要打包的 Rime 方案路径（可以是你已经使用小狼毫等配置好的方案），以及对应的输出名称，自动生成可以导入 Fcitx5 for Android 的压缩包，在 f5a 的导入备份文件中将对应的压缩包进行导入即可。


## 使用方法

```shell
python 小企鹅导入包构建脚本.py 
用法:
  基本用法: python package_rime.py -s <源目录> -o <输出ZIP路径>
  添加模型: python package_rime.py -s <源目录> -m <模型目录> -o <输出ZIP路径>
示例:
  python package_rime.py -s ./rime-data -o ./dist/rime-package.zip
  python package_rime.py -s ./rime-data -m ./models -o ./dist/rime-with-models.zip

```
## Fcitx5 for Android导入步骤
1. 打开输入法的设置
2. 打开高级
3. 导入用户数据, 点确定
4. 选择本脚本打包好的 zip 文件等待完成后即可使用

## 脚本文件

[小企鹅导入包构建脚本.py](小企鹅导入包构建脚本.py)
