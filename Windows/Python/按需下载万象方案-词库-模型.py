import time
import subprocess
import configparser
import requests
import os
import hashlib
import json
from datetime import datetime, timezone, timedelta
import sys
import zipfile
import shutil
import winreg
import fnmatch

# ====================== 全局配置 ======================

# GitHub 仓库信息
OWNER = "amzxyz"
REPO = "rime_wanxiang_pro"
DICT_TAG = "dict-nightly"
# 模型相关配置
MODEL_REPO = "RIME-LMDG"
MODEL_TAG = "LTS"
MODEL_FILE = "wanxiang-lts-zh-hans.gram"


# ====================== 界面函数 ======================
BORDER = "=" * 60
SUB_BORDER = "-" * 55
INDENT = " " * 2
COLOR = {
    "HEADER": "\033[95m",
    "OKBLUE": "\033[94m",
    "OKCYAN": "\033[96m",
    "OKGREEN": "\033[92m",
    "WARNING": "\033[93m",
    "FAIL": "\033[91m",
    "BLACK": "\033[30m",
    "RED": "\033[31m",
    "GREEN": "\033[32m",
    "YELLOW": "\033[33m",
    "BLUE": "\033[34m",
    "MAGENTA": "\033[35m",
    "CYAN": "\033[36m",
    "WHITE": "\033[37m",
    "BOLD": "\033[1m",
    "UNDERLINE": "\033[4m",
    "REVERSE": "\033[7m",
    "ENDC": "\033[0m",

}

def print_header(text):
    print(f"\n{BORDER}")
    print(f"{INDENT}{text.upper()}")
    print(f"{BORDER}")

def print_subheader(text):
    print(f"\n{SUB_BORDER}")
    print(f"{INDENT}* {text}")
    print(f"{SUB_BORDER}")

def print_success(text):
    print(f"{COLOR['OKGREEN']}[√]{COLOR['ENDC']} {text}")

def print_warning(text):
    print(f"{COLOR['OKCYAN']}[!]{COLOR['ENDC']} {text}")

def print_error(text):
    print(f"[×] 错误: {text}")

def print_progress(percentage):
    bar_length = 30
    block = int(round(bar_length * percentage / 100))
    progress = "▇" * block + "-" * (bar_length - block)
    sys.stdout.write(f"\r{INDENT}[{progress}] {percentage:.1f}%")
    sys.stdout.flush()


# ====================== 注册表路径配置 ======================
REG_PATHS = {
    'rime_user_dir': (
        r"Software\Rime\Weasel", 
        "RimeUserDir", 
        winreg.HKEY_CURRENT_USER
    ),
    'weasel_root': (
        r"SOFTWARE\WOW6432Node\Rime\Weasel", 
        "WeaselRoot", 
        winreg.HKEY_LOCAL_MACHINE
    ),
    'server_exe': (
        r"SOFTWARE\WOW6432Node\Rime\Weasel", 
        "ServerExecutable", 
        winreg.HKEY_LOCAL_MACHINE
    )
}

# ====================== 工具函数 ======================
def get_registry_value(key_path, value_name, hive):
    """安全读取注册表值"""
    try:
        with winreg.OpenKey(hive, key_path) as key:
            value, _ = winreg.QueryValueEx(key, value_name)
            return value
    except (FileNotFoundError, PermissionError, OSError):
        return None

def detect_installation_paths():
    """自动检测安装路径"""
    detected = {}
    for key in REG_PATHS:
        path, name, hive = REG_PATHS[key]
        detected[key] = get_registry_value(path, name, hive)
    
    # 智能路径处理
    if detected['weasel_root'] and detected['server_exe']:
        detected['server_exe'] = os.path.join(detected['weasel_root'], detected['server_exe'])
    
    # 设置默认值
    defaults = {
        'rime_user_dir': os.path.join(os.environ['APPDATA'], 'Rime'),
        'weasel_root': r"C:\Program Files (x86)\Rime\weasel-0.16.3",
        'server_exe': r"C:\Program Files (x86)\Rime\weasel-0.16.3\WeaselServer.exe"
    }
    
    for key in detected:
        if not detected[key] or not os.path.exists(detected[key]):
            detected[key] = defaults[key]
    
    return detected

# ====================== 配置管理器 ======================
class ConfigManager:
    """配置管理类"""
    def __init__(self):
        self.config_path = self._get_config_path()
        self.config = configparser.ConfigParser()
        self._ensure_config_exists()

    def _get_config_path(self):
        if getattr(sys, 'frozen', False):
            base_dir = os.path.dirname(sys.executable)
        else:
            base_dir = os.path.dirname(os.path.abspath(__file__))
        return os.path.join(base_dir, 'settings.ini')

    def _ensure_config_exists(self):
        if not os.path.exists(self.config_path):
            self._create_default_config()
            self._guide_scheme_selection()  # 首次运行引导选择方案
            self._show_config_guide()       # 配置引导

    def _create_default_config(self):
        """创建包含自动检测路径的默认配置"""
        paths = detect_installation_paths()
        
        self.config['Settings'] = {
            'custom_dir': os.path.join(paths['rime_user_dir'], 'UpdateCache'),
            'extract_path': paths['rime_user_dir'],
            'dict_extract_path': os.path.join(paths['rime_user_dir'], 'cn_dicts'),
            'weasel_server': paths['server_exe'],
            'scheme_file': 'wanxiang-cj-fuzhu.zip',
            'dict_file': '5-cj_dicts.zip',
            'use_mirror': 'true',
            'exclude_files': ''
        }
        
        # 路径规范化处理
        for key in ['custom_dir', 'extract_path', 'dict_extract_path', 'weasel_server']:
            self.config['Settings'][key] = os.path.normpath(self.config['Settings'][key])
        
        with open(self.config_path, 'w', encoding='utf-8') as f:
            self.config.write(f)

    def _guide_scheme_selection(self):
        """方案选择向导"""
        schemes = {
            '1': {'name': '仓颉', 'scheme_file': 'wanxiang-cj-fuzhu.zip', 'dict_file': '5-cj_dicts.zip'},
            '2': {'name': '小鹤', 'scheme_file': 'wanxiang-flypy-fuzhu.zip', 'dict_file': '2-flypy_dicts.zip'},
            '3': {'name': '汉心', 'scheme_file': 'wanxiang-hanxin-fuzhu.zip', 'dict_file': '8-hanxin_dicts.zip'},
            '4': {'name': '简单鹤', 'scheme_file': 'wanxiang-jdh-fuzhu.zip', 'dict_file': '4-jdh_dicts.zip'},
            '5': {'name': '墨奇', 'scheme_file': 'wanxiang-moqi-fuzhu.zip', 'dict_file': '1-moqi_dicts.zip'},
            '6': {'name': '虎码', 'scheme_file': 'wanxiang-tiger-fuzhu.zip', 'dict_file': '6-tiger_dicts.zip'},
            '7': {'name': '五笔', 'scheme_file': 'wanxiang-wubi-fuzhu.zip', 'dict_file': '7-wubi_dicts.zip'},
            '8': {'name': '自然码', 'scheme_file': 'wanxiang-zrm-fuzhu.zip', 'dict_file': '3-zrm_dicts.zip'},
        }
        
        print(f"\n{BORDER}")
        print(f"{INDENT}首次运行配置向导")
        print(f"{BORDER}")
        print("[1]-仓颉 [2]-小鹤 [3]-汉心 [4]-简单鹤")
        print("[5]-墨奇 [6]-虎码 [7]-五笔 [8]-自然码")
        while True:
            choice = input("请选择默认方案（1-8）: ").strip()
            if choice in schemes:
                selected = schemes[choice]
                # 直接设置方案文件和词库文件到配置
                self.config.set('Settings', 'scheme_file', selected['scheme_file'])
                self.config.set('Settings', 'dict_file', selected['dict_file'])
                with open(self.config_path, 'w', encoding='utf-8') as f:
                    self.config.write(f)
                print(f"{COLOR['OKGREEN']}已选择方案：{selected['name']}{COLOR['ENDC']}")
                return
            print(f"{COLOR['FAIL']}无效的选项{COLOR['ENDC']}")

    def _show_config_guide(self):
        """配置引导界面"""
        # 显示第一个路径检测界面
        print(f"\n{BORDER}")
        print(f"{INDENT}自动检测路径结果")
        print(f"{BORDER}")
        
        detected = detect_installation_paths()
        status_emoji = {True: "✅", False: "❌"}
        for key in detected:
            exists = os.path.exists(detected[key])
            print(f"{INDENT}{key.ljust(15)}: {status_emoji[exists]} {detected[key]}")
        
        print(f"\n{INDENT}生成的配置文件路径: {self.config_path}")
        
        self.display_config_instructions()

        if os.name == 'nt':
            os.startfile(self.config_path)
        input("\n请按需修改上述路径，保存后按回车键继续...")

    def display_config_instructions(self):
        """静默显示配置说明"""
        print_header("请检查配置文件路径,需用户修改")
        print("\n▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂")
        print("使用说明：\n")
        
        path_display = [
            ("[custom_dir]", "存储下载的压缩包和更新时间记录文件", 'custom_dir'),
            ("[extract_path]", "方案解压目录（用户文件夹）", 'extract_path'),
            ("[dict_extract_path]", "词库解压目录", 'dict_extract_path'),
            ("[weasel_server]", "小狼毫服务程序路径", 'weasel_server'),
            ("[scheme_file]", "选择的方案文件名称", 'scheme_file'),
            ("[dict_file]", "关联的词库文件名称", 'dict_file'),
            ("[use_mirror]", "是否打开镜像(镜像网址:bgithub.xyz,默认true)", 'use_mirror'),
            ("[exclude_files]", "更新时需保留的免覆盖文件(默认为空,逗号分隔...格式如下tips_show.txt)", 'exclude_files') 
        ]
        
        for item in path_display:
            print(f"    {item[0].ljust(25)}{item[1]}")
            print(f"        {self.config['Settings'][item[2]]}\n")
        
        print("▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂")
        

    def load_config(self):
        self.config.read(self.config_path, encoding='utf-8')
        config = {k: v.strip('"') for k, v in self.config['Settings'].items()}
        
        # 验证关键路径
        required_paths = {
            '小狼毫服务程序': config['weasel_server'],
            '方案解压目录': config['extract_path'],
            '词库解压目录': config['dict_extract_path']
        }
        # 读取排除文件配置
        exclude_files = [
            pattern.strip() 
            for pattern in self.config.get('Settings', 'exclude_files', fallback='').split(',')
            if pattern.strip()
        ]
        
        missing = [name for name, path in required_paths.items() if not os.path.exists(path)]
        if missing:
            print(f"\n{COLOR['FAIL']}关键路径配置错误：{COLOR['ENDC']}")
            for name in missing:
                print(f"{INDENT}{name}: {required_paths[name]}")
            print(f"\n{INDENT}可能原因：")
            print(f"{INDENT}1. 小狼毫输入法未正确安装")
            print(f"{INDENT}2. 注册表信息被修改")
            print(f"{INDENT}3. 自定义路径配置错误")
            sys.exit(1)
            
        return (
            config['custom_dir'],
            config['scheme_file'],
            config['extract_path'],
            config['dict_extract_path'],
            config['weasel_server'],
            self.config.getboolean('Settings', 'use_mirror'),
            config['dict_file'],
            exclude_files
        )

# ====================== 更新基类 ======================
class UpdateHandler:
    """更新系统核心基类"""
    def __init__(self, config_manager):
        self.config_manager = config_manager
        (
            self.custom_dir,
            self.scheme_file,
            self.extract_path,
            self.dict_extract_path,
            self.weasel_server,
            self.use_mirror,
            self.dict_file,
            self.exclude_files
        ) = config_manager.load_config()
        self.ensure_directories()

    def ensure_directories(self):
        """目录保障系统"""
        os.makedirs(self.custom_dir, exist_ok=True)
        os.makedirs(self.extract_path, exist_ok=True)
        os.makedirs(self.dict_extract_path, exist_ok=True)

    def github_api_request(self, url):
        """GitHub API 安全请求"""
        try:
            response = requests.get(url)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print_error(f"API请求失败: {str(e)}")
            return None

    def mirror_url(self, url):
        """智能镜像处理"""
        return url.replace("github.com", "bgithub.xyz") if self.use_mirror else url

    def download_file(self, url, save_path):
        """带进度显示的稳健下载"""
        try:
            response = requests.get(url, stream=True)
            total_size = int(response.headers.get('content-length', 0))
            block_size = 8192
            downloaded = 0
            
            with open(save_path, 'wb') as f:
                for data in response.iter_content(block_size):
                    f.write(data)
                    downloaded += len(data)
                    progress = (downloaded / total_size) * 100 if total_size else 0
                    print_progress(progress)
            print()
            return True
        except Exception as e:
            print_error(f"下载失败: {str(e)}")
            return False

    def extract_zip(self, zip_path, target_dir, is_dict=False):
        """智能解压系统（支持排除文件）"""
        try:
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                exclude_patterns = self.exclude_files  # 获取排除模式
                if is_dict:
                    # 处理词库多级目录（应用排除规则）
                    members = [m for m in zip_ref.namelist() if not m.endswith('/')]
                    common_prefix = os.path.commonpath(members) if members else ''
                    for member in members:
                        relative_path = os.path.relpath(member, common_prefix)
                        # 转换为系统路径分隔符
                        normalized_path = os.path.normpath(relative_path.replace('/', os.sep))
                        file_name = os.path.basename(normalized_path)
                        # 检查排除规则
                        exclude = any(
                            fnmatch.fnmatch(normalized_path, pattern) or 
                            fnmatch.fnmatch(file_name, pattern)
                            for pattern in exclude_patterns
                        )
                        if exclude:
                            print_warning(f"跳过排除文件: {normalized_path}")
                            continue
                        target_path = os.path.join(target_dir, normalized_path)
                        os.makedirs(os.path.dirname(target_path), exist_ok=True)
                        with open(target_path, 'wb') as f:
                            f.write(zip_ref.read(member))
                else:
                    # 保持方案文件结构（应用排除规则）
                    base_dir = os.path.splitext(os.path.basename(zip_path))[0] + "/"
                    exclude_patterns = self.exclude_files
                    for member in zip_ref.namelist():
                        if member.startswith(base_dir) and not member.endswith('/'):
                            relative_path = member[len(base_dir):]
                            # 统一路径分隔符为当前系统格式
                            normalized_path = os.path.normpath(relative_path.replace('/', os.sep))
                            # 获取纯文件名部分
                            file_name = os.path.basename(normalized_path)
                            
                            # 检查是否匹配排除规则（支持路径模式和纯文件名）
                            exclude = any(
                                # 匹配完整路径或纯文件名
                                fnmatch.fnmatch(normalized_path, pattern) or 
                                fnmatch.fnmatch(file_name, pattern)
                                for pattern in exclude_patterns
                            )
                            
                            if exclude:
                                print_warning(f"跳过排除文件: {normalized_path}")
                                continue
                            target_path = os.path.join(target_dir, relative_path)
                            os.makedirs(os.path.dirname(target_path), exist_ok=True)
                            with open(target_path, 'wb') as f:
                                f.write(zip_ref.read(member))
            return True
        except zipfile.BadZipFile:
            print_error("ZIP文件损坏")
            return False
        except Exception as e:
            print_error(f"解压失败: {str(e)}")
            return False

    def terminate_processes(self):
        """组合式进程终止策略"""
        if not self.graceful_stop():  # 先尝试优雅停止
            self.hard_stop()          # 失败则强制终止

    def graceful_stop(self):
        """优雅停止服务"""
        try:
            subprocess.run(
                [self.weasel_server, "/q"],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            print_success("服务已优雅退出")
            return True
        except subprocess.CalledProcessError as e:
            print_warning(f"优雅退出失败: {e}")
            return False
        except Exception as e:
            print_error(f"未知错误: {str(e)}")
            return False

    def hard_stop(self):
        """强制终止保障"""
        print_subheader("强制终止残留进程")
        for _ in range(3):
            subprocess.run(["taskkill", "/IM", "WeaselServer.exe", "/F"], 
                         shell=True, stderr=subprocess.DEVNULL)
            subprocess.run(["taskkill", "/IM", "WeaselDeployer.exe", "/F"], 
                         shell=True, stderr=subprocess.DEVNULL)
            time.sleep(0.5)
        print_success("进程清理完成")

    def deploy_weasel(self):
        """智能部署引擎"""
        try:
            self.terminate_processes()
            
            # 服务启动重试机制
            for retry in range(3):
                try:
                    print_subheader("启动小狼毫服务")
                    subprocess.Popen(
                        [self.weasel_server],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        creationflags=subprocess.CREATE_NO_WINDOW
                    )
                    time.sleep(2)
                    break
                except Exception as e:
                    if retry == 2:
                        raise
                    print_warning(f"服务启动失败，重试({retry+1}/3)...")
                    time.sleep(1)
            
            # 部署执行与验证
            print_subheader("执行部署操作")
            deployer = os.path.join(os.path.dirname(self.weasel_server), "WeaselDeployer.exe")
            result = subprocess.run(
                [deployer, "/deploy"],
                capture_output=True,
                text=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            if result.returncode != 0:
                raise Exception(f"部署失败: {result.stderr.strip()}")
                
            print_success("部署成功完成")
            return True
        except Exception as e:
            print_error(f"部署失败: {str(e)}")
            return False


# ====================== 方案更新 ======================
class SchemeUpdater(UpdateHandler):
    """方案更新处理器"""
    def __init__(self, config_manager):
        super().__init__(config_manager)
        self.record_file = os.path.join(self.custom_dir, "scheme_record.json")

    def check_update(self):
        releases = self.github_api_request(f"https://api.github.com/repos/{OWNER}/{REPO}/releases")
        if not releases:
            return None

        for release in releases[:2]:  # 检查前两个发布
            for asset in release.get("assets", []):
                if asset["name"] == self.scheme_file:
                    return {
                        "url": self.mirror_url(asset["browser_download_url"]),
                        "published_at": release["published_at"],
                        "tag": release["tag_name"]
                    }
        return None

    def run(self):
        print_header("方案更新流程")
        remote_info = self.check_update()
        if not remote_info:
            print_warning("未找到可用更新")
            return False  # 返回False表示没有更新
        remote_info = self.check_update()

        # 时间比较
        remote_time = datetime.strptime(remote_info["published_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        local_time = self.get_local_time()
        
        if local_time and remote_time <= local_time:
            print_success("当前已是最新方案")
            return False  # 没有更新

        # 检测到更新时的提示
        china_time = remote_time.astimezone(timezone(timedelta(hours=8)))
        print_warning(f"检测到方案更新（标签：{remote_info['tag']}），发布时间：{china_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print_subheader("准备开始下载方案文件...")

        # 下载更新
        temp_file = os.path.join(self.custom_dir, "temp_scheme.zip")
        if not self.download_file(remote_info["url"], temp_file):
            return False

        # 校验文件
        target_file = os.path.join(self.custom_dir, self.scheme_file)
        if os.path.exists(target_file) and self.file_compare(temp_file, target_file):
            print_success("文件内容未变化")
            os.remove(temp_file)
            # 保存远程信息到记录文件
            with open(self.record_file, 'w') as f:
                json.dump({
                    "tag": remote_info["tag"],
                    "published_at": remote_info["published_at"],
                    "update_time": datetime.now(timezone.utc).isoformat()
                }, f)
            return False

        # 应用更新
        self.apply_update(temp_file, os.path.join(self.custom_dir, self.scheme_file), remote_info)
        self.clean_build()
        print_success("方案更新完成")
        return True  # 成功更新

    def get_local_time(self):
        if not os.path.exists(self.record_file):
            return None
            
        try:
            with open(self.record_file, 'r') as f:
                data = json.load(f)
                return datetime.strptime(data["published_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except:
            return None

    def file_compare(self, file1, file2):
        hash1 = calculate_sha256(file1)
        hash2 = calculate_sha256(file2)
        return hash1 == hash2

    def apply_update(self, temp, target, info):
        # 新增终止进程步骤
        self.terminate_processes()
        # 替换文件
        if os.path.exists(target):
            os.remove(target)
        os.rename(temp, target)
        
        # 解压文件
        if not self.extract_zip(target, self.extract_path):
            raise Exception("解压失败")
        
        # 保存记录
        with open(self.record_file, 'w') as f:
            json.dump({
                "tag": info["tag"],
                "published_at": info["published_at"],
                "update_time": datetime.now(timezone.utc).isoformat()
            }, f)

    def clean_build(self):
        build_dir = os.path.join(self.extract_path, "build")
        if os.path.exists(build_dir):
            shutil.rmtree(build_dir)
            print_success("已清理build目录")
            

# ====================== 词库更新 ======================
class DictUpdater(UpdateHandler):
    """词库更新处理器"""
    def __init__(self, config_manager):
        super().__init__(config_manager)
        self.target_tag = DICT_TAG  # 使用全局配置的标签
        self.target_file = os.path.join(self.custom_dir, self.dict_file)  
        self.temp_file = os.path.join(self.custom_dir, "temp_dict.zip")   
        self.record_file = os.path.join(self.custom_dir, "dict_record.json")

    def check_update(self):
        """检查更新"""
        release = self.github_api_request(
            f"https://api.github.com/repos/{OWNER}/{REPO}/releases/tags/{self.target_tag}"
        )
        if not release:
            return None

        # 精确匹配配置中的词库文件
        target_asset = next(
            (a for a in release["assets"] if a["name"] == self.dict_file),
            None
        )
        if not target_asset:
            return None

        return {
            "url": self.mirror_url(target_asset["browser_download_url"]),
            "published_at": release["published_at"],  # 使用release时间
            "tag": release["tag_name"],
            "size": target_asset["size"]
        }

    def get_local_time(self):
        """获取本地记录时间"""
        if not os.path.exists(self.record_file):
            return None
        try:
            with open(self.record_file, 'r') as f:
                data = json.load(f)
                return datetime.strptime(data["published_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except:
            return None

    def file_compare(self, file1, file2):
        """文件比对"""
        return calculate_sha256(file1) == calculate_sha256(file2)

    def apply_update(self, temp, target, info):
        """ 参数不再需要传递路径，使用实例变量 """
        try:
            # 终止进程
            self.terminate_processes()
            # 替换文件（使用明确的实例变量）
            if os.path.exists(target):
                os.remove(target)
            os.rename(temp, target)
            # 解压到配置目录
            if not self.extract_zip(
                self.target_file,
                self.dict_extract_path,
                is_dict=True
            ):
                raise Exception("解压失败")
        
            # 保存记录
            with open(self.record_file, 'w') as f:
                json.dump({
                    "dict_file": self.dict_file,
                    "published_at": info["published_at"],
                    "tag": info["tag"],
                    "update_time": datetime.now(timezone.utc).isoformat()
                }, f)

        except Exception as e:
            # 清理残留文件
            if os.path.exists(self.temp_file):
                os.remove(self.temp_file)
            raise

    def run(self):
        """执行更新"""
        print_header("词库更新流程")
        remote_info = self.check_update()
        if not remote_info:
            print_warning("未找到可用更新")
            return False

        # 时间比对（精确到秒）
        remote_time = datetime.strptime(remote_info["published_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        local_time = self.get_local_time()
        
        if local_time and remote_time <= local_time:
            print_success("当前已是最新词库")
            return False

        # 更新提示
        print_warning(f"检测到词库更新（标签：{remote_info['tag']}）")
        china_time = remote_time.astimezone(timezone(timedelta(hours=8)))
        print_subheader(f"发布时间：{china_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"{INDENT}文件大小：{remote_info['size']/1024:.1f} KB")

        # 下载流程
        temp_file = os.path.join(self.custom_dir, "temp_dict.zip")
        target_file = os.path.join(self.custom_dir, self.dict_file)
        if not self.download_file(remote_info["url"], temp_file):
            return False

        # 哈希校验
        if os.path.exists(target_file) and self.file_compare(temp_file, target_file):
            print_success("文件内容未变化")
            os.remove(temp_file)
            # 更新本地记录
            with open(self.record_file, 'w') as f:
                json.dump({
                    "published_at": remote_info["published_at"],
                    "tag": remote_info["tag"],
                    "update_time": datetime.now(timezone.utc).isoformat()
                }, f)
            return False

        try:
            self.apply_update(temp_file, target_file, remote_info)  # 传递三个参数
            print_success("词库更新完成")
            return True
        except Exception as e:
            print_error(f"更新失败: {str(e)}")
            # 回滚临时文件
            if os.path.exists(temp_file):
                os.remove(temp_file)
            return False

# ====================== 模型更新 ======================
class ModelUpdater(UpdateHandler):
    """模型更新处理器"""
    def __init__(self, config_manager):
        super().__init__(config_manager)
        self.record_file = os.path.join(self.custom_dir, "model_record.json")
        # 模型固定配置
        self.model_file = "wanxiang-lts-zh-hans.gram"
        self.temp_file = os.path.join(self.custom_dir, f"{self.model_file}.tmp") 
        self.target_path = os.path.join(self.extract_path, self.model_file) 

    def check_update(self):
        """检查模型更新"""
        release = self.github_api_request(
            f"https://api.github.com/repos/{OWNER}/{MODEL_REPO}/releases/tags/{MODEL_TAG}"
        )
        if not release:
            return None
            
        # 查找目标模型文件
        for asset in release.get("assets", []):
            if asset["name"] == self.model_file:
                return {
                    "url": self.mirror_url(asset["browser_download_url"]),  # 镜像处理
                    "published_at": asset["updated_at"],  # 使用asset更新时间
                    "size": asset["size"]
                }
        return None

    def mirror_url(self, url):
        """镜像URL处理（复用现有逻辑）"""
        return url.replace("github.com", "bgithub.xyz") if self.use_mirror else url

    def run(self):
        """执行模型更新主流程"""
        print_header("模型更新流程")
        remote_info = self.check_update()
        if not remote_info:
            print_warning("未找到模型更新信息")
            return False

        # 时间比较（本地记录 vs 远程发布时间）
        remote_time = datetime.strptime(remote_info["published_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        local_time = self._get_local_record_time()
        
        if local_time and remote_time <= local_time:
            print_success("当前模型已是最新版本")
            return False

        # 检测到更新时的提示
        china_time = remote_time.astimezone(timezone(timedelta(hours=8)))
        print_warning(f"检测到模型更新，最新版本发布时间：{china_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print_subheader("准备开始下载模型文件...")


        # 下载到临时文件
        if not self.download_file(remote_info["url"], self.temp_file):
            print_error("模型下载失败")
            return False

        # 无论是否有记录，都检查哈希是否匹配
        hash_matched = self._check_hash_match()
        remote_time = datetime.strptime(remote_info["published_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        local_time = self._get_local_record_time()

        # 哈希匹配但记录缺失时的处理
        if hash_matched:
            print_success("模型内容未变化")
            os.remove(self.temp_file)
            # 强制更新记录（解决记录文件丢失的问题）
            if not local_time or remote_time > local_time:
                self._save_update_record(remote_info["published_at"])
            return False


        # 停止服务再覆盖
        self.terminate_processes()  # 复用终止进程逻辑
        
        # 覆盖目标文件
        try:
            if os.path.exists(self.target_path):
                os.remove(self.target_path)
            os.replace(self.temp_file, self.target_path)  # 原子操作更安全
        except Exception as e:
            print_error(f"模型文件替换失败: {str(e)}")
            return False

        # 保存更新记录
        self._save_update_record(remote_info["published_at"])
        
        # 返回更新成功状态
        print_success("模型更新完成")
        return True

    def _get_local_record_time(self):
        """获取本地记录的最后更新时间"""
        if not os.path.exists(self.record_file):
            return None
        try:
            with open(self.record_file, "r") as f:
                data = json.load(f)
                return datetime.strptime(data["last_updated"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except:
            return None

    def _check_hash_match(self):
        """检查临时文件与目标文件哈希是否一致"""
        temp_hash = calculate_sha256(self.temp_file)
        target_hash = calculate_sha256(self.target_path) if os.path.exists(self.target_path) else None
        return temp_hash == target_hash

    def _save_update_record(self, published_at):
        """保存更新时间记录到custom_dir"""
        record = {
            "model_name": self.model_file,
            "last_updated": published_at,
            "update_time": datetime.now(timezone.utc).isoformat()
        }
        with open(self.record_file, "w") as f:
            json.dump(record, f, indent=2)


# ====================== 工具函数 ======================
def calculate_sha256(file_path):
    """计算文件SHA256值"""
    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except Exception as e:
        print_error(f"计算哈希失败: {str(e)}")
        return None



# ====================== 主程序 ======================
def main():
    try:
        # 初始化配置
        config_manager = ConfigManager()
        config_loaded = False

        # 加载并验证配置
        try:
            settings = config_manager.load_config()
            print(f"\n{COLOR['GREEN']}[√] 配置加载成功{COLOR['ENDC']}")
            print(f"{INDENT}▪ 方案文件：{settings[1]}")
            print(f"{INDENT}▪ 词库文件：{settings[6]}")
            print(f"{INDENT}▪ 服务程序：{settings[4]}")
        except Exception as e:
            print(f"\n{COLOR['FAIL']}❌ 配置加载失败：{str(e)}{COLOR['ENDC']}")
            sys.exit(1)

        # 检查是否初次运行
        if not os.path.exists(config_manager.config_path):
            print_header("首次运行配置向导")
            print("检测到初次运行，正在创建默认配置...")
            config_loaded = True
        else:
            # 直接加载现有配置
            config = config_manager.load_config()
            config_loaded = True

        # 选择更新类型
        print_header("更新类型选择") 
        print("[1] 词库更新\n[2] 方案更新\n[3] 模型更新\n[4] 全部更新\n[5] 修改配置")  # 新增模型更新选项
        choice = input("请输入选择（1-5，单独按回车键默认选择全部更新）: ").strip() or '4'
        
        if choice == '5':
            config_manager.display_config_instructions()
            print("保存后关闭配置文件以继续...")

            # 用记事本打开配置文件（阻塞方式）
            if os.name == 'nt':
                subprocess.run(['notepad.exe', config_manager.config_path], shell=True)
            else:
                subprocess.call(['open', config_manager.config_path])
            print_success("配置文件修改已完成")
            
            # 交互逻辑
            user_choice = input("\n按回车键退出程序，或输入 z 返回主菜单: ").strip().lower()
            if user_choice == 'z':
                main()  # 重新进入主程序
            else:
                print("\n✨ 配置修改已完成，欢迎下次使用！")
                sys.exit(0)
                
        # 执行更新
        updated = False
        deployer = None  # 确保在所有分支前初始化
        if choice == '1':
            updater = DictUpdater(config_manager)
            updated = updater.run()
            deployer = updater  # 明确指定部署器
        elif choice == '2':
            updater = SchemeUpdater(config_manager)
            updated = updater.run()
            deployer = updater  # 明确指定部署器
        elif choice == '3':
            updater = ModelUpdater(config_manager)
            updated = updater.run()
            deployer = updater  # 明确指定部署器
        elif choice == '4':
            # 全部更新模式
            deployer = SchemeUpdater(config_manager)  # 指定方案更新器为部署器
            scheme_updated = deployer.run()           # 使用同一个实例执行更新
            
            dict_updater = DictUpdater(config_manager)
            dict_updated = dict_updater.run()
            
            model_updater = ModelUpdater(config_manager)
            model_updated = model_updater.run()
            
            updated = scheme_updated or dict_updated or model_updated
        else:
            print_error("无效的选项")
            return
        # 统一部署检查（安全判断）
        if updated and deployer:  # 双重条件判断
            print_header("重新部署输入法")
            if deployer.deploy_weasel():
                print_success("部署成功")
            else:
                print_warning("部署失败，请检查日志")
        else:
            print("\n" + COLOR['OKCYAN'] + "[i]" + COLOR['ENDC'] + " 未进行更新，跳过部署步骤")

        

            
    except Exception as e:
        print(f"\n{COLOR['FAIL']}💥 程序异常：{str(e)}{COLOR['ENDC']}")
        sys.exit(1)
        
if __name__ == "__main__":
    while True:
        main()
        user_input = input("\n按回车键退出程序，或输入 z 返回主菜单: ")
        if user_input.strip().lower() != 'z':
            print("\n✨ 升级完毕，欢迎下次使用！")
            time.sleep(2)
            break

