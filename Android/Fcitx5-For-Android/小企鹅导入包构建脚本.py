import os
import shutil
import json
import subprocess
import sys
import tempfile
import time
import argparse
from pathlib import Path
import winreg

def create_zip_package(source_dir, output_zip, model_path=None):
    """
    创建符合要求的ZIP包，跳过.git/.github/build目录和.gitignore/.gitattributes文件
    可选添加模型目录内容到ZIP包中
    """
    # 验证源目录是否存在
    if not os.path.isdir(source_dir):
        print(f"错误: 源目录不存在 - {source_dir}")
        sys.exit(1)
    
    # 如果提供了模型目录，验证其是否存在
    if model_path and not os.path.exists(model_path):
        print(f"错误: 模型文件不存在 - {model_path}")
        sys.exit(1)
    
    # 创建临时工作目录
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_dir_path = Path(temp_dir)
        
        # 创建目标目录结构
        dest_rime = temp_dir_path / "external" / "data" / "rime"
        os.makedirs(dest_rime, exist_ok=True)
        
        # 定义要跳过的目录和文件
        skip_dirs = {'.git', '.github', 'build'}  # 使用集合提高查找效率
        skip_files = {'.gitignore', '.gitattributes'}
        
        # ========== 步骤1: 复制源目录内容 ==========
        print(f"正在复制源目录文件: {source_dir} -> {dest_rime}")
        
        for root, dirs, files in os.walk(source_dir):
            # 从当前遍历中移除要跳过的目录
            dirs[:] = [d for d in dirs if d not in skip_dirs]
            
            # 计算目标路径
            rel_path = os.path.relpath(root, source_dir)
            dest_path = dest_rime / rel_path
            
            # 创建目标子目录
            os.makedirs(dest_path, exist_ok=True)
            
            # 复制文件（跳过指定文件）
            print(f"  正在复制目录: {root} 到 {dest_path}") # 简化复制输出
            for file in files:
                if file in skip_files:
                    print(f"  跳过文件: {os.path.join(root, file)}")
                    continue
                
                src_file = os.path.join(root, file)
                dst_file = dest_path / file
                shutil.copy2(src_file, dst_file)
                # print(f"  已复制: {src_file} -> {dst_file}") # 简化复制输出
        
        # ========== 步骤2: 可选添加模型目录内容 ==========
        if model_path:
            # 计算目标路径
            model_file_name = os.path.basename(model_path)
            src_file = model_path
            dst_file = dest_rime / model_file_name
            print(f"\n正在添加模型文件: {src_file} -> {dst_file}")
            # 如果文件已存在，覆盖它
            if os.path.exists(dst_file):
                print(f"  覆盖: {dst_file}")
            shutil.copy2(src_file, dst_file)
            print(f"  已添加: {src_file} -> {dst_file}")
        
        # ========== 步骤3: 创建元数据文件 ==========
        current_time_ms = int(time.time() * 1000)
        metadata = {
            "packageName": "org.fcitx.fcitx5.android",
            "versionCode": 92,
            "versionName": "0.1.1-14-gdf4e1349-release",
            "exportTime": current_time_ms
        }
        metadata_path = temp_dir_path / "metadata.json"
        with open(metadata_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2)
        print(f"\n已创建元数据文件: {metadata_path}")
        print(f"  导出时间戳: {current_time_ms} ({time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(current_time_ms/1000))})")
        
        # ========== 步骤4: 创建ZIP包 ==========
        # 确保输出目录存在
        output_dir = os.path.dirname(output_zip)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        print(f"\n正在创建ZIP包: {output_zip}")
        base_dir = temp_dir_path  # ZIP包的根目录
        
        # 创建临时ZIP文件
        temp_zip = shutil.make_archive(
            base_name=os.path.splitext(output_zip)[0],
            format='zip',
            root_dir=base_dir,
            base_dir='.',  # 包含整个目录内容
            verbose=True
        )
        
        # 移动到目标位置
        shutil.move(temp_zip, output_zip)
        print(f"\nZIP包创建成功: {output_zip}")
        print(f"源目录中的.git/.github/build文件夹和.gitignore/.gitattributes文件保持原样未修改")
        if model_path:
            print(f"模型文件内容已添加到ZIP包中")

# 照着win-mac-ios融合版抄来的代码
if sys.platform == 'win32':
    def terminate_processes():
        """组合式进程终止策略"""
        if not graceful_stop():  # 先尝试优雅停止
            hard_stop()          # 失败则强制终止

    def graceful_stop():
        """优雅停止服务"""

        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Rime\Weasel") as key:
                exe, _ = winreg.QueryValueEx(key, "ServerExecutable")
                root, _ = winreg.QueryValueEx(key, "WeaselRoot")
                value = os.path.join(root, exe)
            subprocess.run(
                [value, "/q"],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            print(f"{exe} 服务已优雅退出")
            return True
        except subprocess.CalledProcessError as e:
            print(f"优雅退出失败: {e}")
            return False
        except (FileNotFoundError, PermissionError, OSError) as e:
            print(f"优雅退出失败: {e}")
            return False
        except Exception as e:
            print(f"未知错误: {str(e)}")
            return False

    def hard_stop():
        """强制终止保障"""
        print("强制终止残留进程")
        for _ in range(3):
            subprocess.run(["taskkill", "/IM", "WeaselServer.exe", "/F"], 
                        shell=True, stderr=subprocess.DEVNULL)
            subprocess.run(["taskkill", "/IM", "WeaselDeployer.exe", "/F"], 
                        shell=True, stderr=subprocess.DEVNULL)
            time.sleep(0.5)
        print("进程清理完成")

def main():
    parser = argparse.ArgumentParser(description="打包 Rime 文件目录为 zip 包")

    parser.add_argument("--source", "-s", required=True, help="源目录")
    parser.add_argument("--output", "-o", required=True, help="输出 zip 路径")
    parser.add_argument("--model", "-m", help="模型目录（可选）", default=None)

    args = parser.parse_args()
    terminate_processes() # 在复制前终止相关进程
    create_zip_package(args.source, args.output, args.model)




if __name__ == "__main__":
    main()
