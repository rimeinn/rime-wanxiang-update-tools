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
import fnmatch
import re

# ====================== 全局配置 ======================

# GitHub 仓库信息
OWNER = "amzxyz"
REPO = "rime_wanxiang_pro"
DICT_TAG = "dict-nightly"
# 模型相关配置
MODEL_REPO = "RIME-LMDG"
MODEL_TAG = "LTS"
MODEL_FILE = "wanxiang-lts-zh-hans.gram"

SCHEME_MAP = {
    '1': 'cj',
    '2': 'flypy',
    '3': 'hanxin',
    '4': 'jdh', 
    '5': 'moqi',
    '6': 'tiger',
    '7': 'wubi',
    '8': 'zrm'
}
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


# ====================== 工具函数 ======================
def detect_installation_paths(dir: str):
    if os.path.exists(dir):
        print_success(f"检测到安装或配置目录: {dir}")
        return True
    print_warning(f"未检测到安装或配置目录: {dir}")
    return False


# ====================== 配置管理器 ======================
class ConfigManager:
    """配置管理类"""
    def __init__(self):
        self.config_path = self._get_config_path()
        self.config = configparser.ConfigParser()
        self._ensure_config_exists()
        self.rime_engine = ''
        self.rime_dir = ''

    def _get_config_path(self):
        if getattr(sys, 'frozen', False):
            base_dir = os.path.dirname(sys.executable)
        else:
            base_dir = os.path.dirname(os.path.abspath(__file__))
        return os.path.join(base_dir, 'settings.ini')

    def _ensure_config_exists(self):
        if not os.path.exists(self.config_path):
            self._select_rime_engine()  # 首次运行选择引擎
            self._create_default_config()
            self._guide_scheme_selection()  # 首次运行引导选择方案
            self._show_config_guide()       # 配置引导

    def _select_rime_engine(self):
        """选择输入法引擎：鼠须管/小企鹅"""
        print(f"\n{BORDER}")
        print(f"{INDENT}首次运行引擎选择向导")
        print(f"{BORDER}")
        print("[1]-鼠须管Squirrel [2]-小企鹅Fcitx5")

        while True:
            choice = input(f"{INDENT}请选择输入法引擎：").strip()
            if choice == '1':
                self.rime_dir = os.path.expanduser('~/Library/Rime')
                self.rime_engine = '鼠须管'
                return
            elif choice == '2':
                self.rime_dir = os.path.expanduser('~/.local/share/fcitx5/rime')
                self.rime_engine = '小企鹅'
                return
            else:
                print(f"{INDENT}无效的选择，请重新选择。")
                
                
    def _create_default_config(self):
        """创建包含自动检测路径的默认配置"""
        path = detect_installation_paths(self.rime_dir)
        
        if path:
            self.config['Settings'] = {
                'custom_dir': os.path.join(self.rime_dir, 'UpdateCache'),
                'extract_path': self.rime_dir,
                'dict_extract_path': os.path.join(self.rime_dir, 'cn_dicts'),
                'scheme_file': '',
                'dict_file': '',
                'use_mirror': 'true',
                'github_token': '',
                'exclude_files': '',
                'engine': self.rime_engine
            }
        
            # 路径规范化处理
            for key in ['custom_dir', 'extract_path', 'dict_extract_path']:
                self.config['Settings'][key] = os.path.normpath(self.config['Settings'][key])
            
            with open(self.config_path, 'w', encoding='utf-8') as f:
                self.config.write(f)

    def _guide_scheme_selection(self):
        print(f"\n{BORDER}")
        print(f"{INDENT}首次运行配置向导")
        print(f"{BORDER}")
        print("[1]-仓颉 [2]-小鹤 [3]-汉心 [4]-简单鹤")
        print("[5]-墨奇 [6]-虎码 [7]-五笔 [8]-自然码")
        
        while True:
            choice = input("请选择你的辅助码方案（1-8）: ").strip()
            if choice in SCHEME_MAP:
                scheme_key = SCHEME_MAP[choice]
                
                # 立即获取实际文件名
                scheme_file, dict_file = self._get_actual_filenames(scheme_key)
                
                # 更新配置文件
                self.config.set('Settings', 'scheme_file', scheme_file)
                self.config.set('Settings', 'dict_file', dict_file)
                # 添加编码参数
                with open(self.config_path, 'w', encoding='utf-8') as f:
                    self.config.write(f)
                
                print_success(f"已选择方案：{scheme_key.upper()}")
                print(f"方案文件: {scheme_file}")
                print(f"词库文件: {dict_file}")
                return
            print_error("无效的选项，请重新输入")
    def _get_actual_filenames(self, scheme_key):
        """获取实际文件名（带网络请求）"""
        try:
            # 方案文件检查器（使用最新Release）
            scheme_checker = GithubFileChecker(
                owner=OWNER,
                repo=REPO,
                pattern=f"wanxiang-{scheme_key}*.zip"
            )
            # 词库文件检查器（使用dict-nightly标签）
            dict_checker = GithubFileChecker(
                owner=OWNER,
                repo=REPO,
                pattern=f"*{scheme_key}*.zip",
                tag=DICT_TAG
            )
            
            # 获取最新文件名
            scheme_file = scheme_checker.get_latest_file()
            dict_file = dict_checker.get_latest_file()
            
            # 确保返回有效文件名
            if not scheme_file or '*' in scheme_file:
                raise ValueError("无法获取有效的方案文件名")
            if not dict_file or '*' in dict_file:
                raise ValueError("无法获取有效的词库文件名")
                
            return scheme_file, dict_file
            
        except Exception as e:
            print_warning(f"无法获取最新文件名，使用默认模式: {str(e)}")
            return (
                f"wanxiang-{scheme_key}-fuzhu.zip",
                f"*-{scheme_key}_dicts.zip"
            )

    def _show_config_guide(self):
        """配置引导界面"""
        # 显示第一个路径检测界面
        print(f"\n{BORDER}")
        print(f"{INDENT}自动检测路径结果")
        print(f"{BORDER}")
        
        detected = detect_installation_paths(self.config_path)
        status_emoji = {True: "✅", False: "❌"}
        if detected:
            name = '配置文件'
            print(f"{INDENT}{name.ljust(15)}: {status_emoji[detected]} {self.config_path}")
        
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
            ("[scheme_file]", "选择的方案文件名称", 'scheme_file'),
            ("[dict_file]", "关联的词库文件名称", 'dict_file'),
            ("[use_mirror]", "是否打开镜像(镜像网址:bgithub.xyz,默认true)", 'use_mirror'),
            ("[github_token]", "GitHub令牌(可选)", 'github_token'),
            ("[exclude_files]", "更新时需保留的免覆盖文件(默认为空,逗号分隔...格式如下tips_show.txt)", 'exclude_files'), 
            ("[engine]", "选择的输入法引擎", 'engine')
        ]
        
        for item in path_display:
            print(f"    {item[0].ljust(25)}{item[1]}")
            print(f"        {self.config['Settings'][item[2]]}\n")
        
        print("▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂")
        

    def load_config(self):
        self.config.read(self.config_path, encoding='utf-8')
        config = {k: v.strip('"') for k, v in self.config['Settings'].items()}
        github_token = config.get('github_token', '')
        # 验证关键路径
        required_paths = {
            '方案解压目录': config['extract_path'],
            '词库解压目录': config['dict_extract_path']
        }
        # 读取排除文件配置
        exclude_files = [
            pattern.strip() 
            for pattern in re.split(r',|，', self.config.get('Settings', 'exclude_files', fallback=''))  # 同时分割中英文逗号
            if pattern.strip()
        ]
        
        missing = [name for name, path in required_paths.items() if not os.path.exists(path)]
        if missing:
            print(f"\n{COLOR['FAIL']}关键路径配置错误：{COLOR['ENDC']}")
            for name in missing:
                print(f"{INDENT}{name}: {required_paths[name]}")
            print(f"\n{INDENT}可能原因：")
            print(f"{INDENT}1. 鼠须管或小企鹅输入法未正确安装")
            print(f"{INDENT}2. 自定义路径配置错误")
            sys.exit(1)
            
        return (
            config['custom_dir'],
            config['scheme_file'],
            config['extract_path'],
            config['dict_extract_path'],
            self.config.getboolean('Settings', 'use_mirror'),
            config['dict_file'],
            exclude_files,
            github_token,
            config['engine']
        )

class GithubFileChecker:
    def __init__(self, owner, repo, pattern, tag=None):
        self.owner = owner
        self.repo = repo
        self.pattern_regex = re.compile(pattern.replace('*', '.*'))
        self.tag = tag  # 新增标签参数

    def get_latest_file(self):
        """获取匹配模式的最新文件"""
        releases = self._get_releases()
        for release in releases:
            for asset in release.get("assets", []):
                if self.pattern_regex.match(asset['name']):
                    return asset['name']
        return None  # 如果未找到，返回None

    def _get_releases(self):
        """根据标签获取对应的Release"""
        if self.tag:
            # 获取指定标签的Release
            url = f"https://api.github.com/repos/{self.owner}/{self.repo}/releases/tags/{self.tag}"
        else:
            # 获取所有Release（按时间排序）
            url = f"https://api.github.com/repos/{self.owner}/{self.repo}/releases"
        
        response = requests.get(url)
        response.raise_for_status()
        # 返回结果处理：指定标签时为单个Release，否则为列表
        return [response.json()] if self.tag else response.json()




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
            self.use_mirror,
            self.dict_file,
            self.exclude_files,
            self.github_token,
            self.engine
        ) = config_manager.load_config()
        self.ensure_directories()

    def ensure_directories(self):
        """目录保障系统"""
        os.makedirs(self.custom_dir, exist_ok=True)
        os.makedirs(self.extract_path, exist_ok=True)
        os.makedirs(self.dict_extract_path, exist_ok=True)

    def github_api_request(self, url):
        """带令牌认证的API请求"""
        headers = {"User-Agent": "RIME-Updater/1.0"}
        if not self.github_token:
            return None
        
        headers["Authorization"] = f"Bearer {self.github_token}"
        try:
            return requests.get(url, headers=headers).json()
        except requests.RequestException:
            return None

    def mirror_url(self, url):
        """智能镜像处理"""
        return url.replace("github.com", "bgithub.xyz") if self.use_mirror else url

    def download_file(self, url, save_path):
        """带进度显示的稳健下载"""
        try:
            # 统一提示镜像状态
            if self.use_mirror:
                print(f"{COLOR['OKBLUE']}[i] 正在使用镜像 https://bgithub.xyz 下载{COLOR['ENDC']}")
            else:
                print(f"{COLOR['OKCYAN']}[i] 正在使用 https://github.com 下载{COLOR['ENDC']}")
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
        for release in releases[:2]:
            for asset in release.get("assets", []):
                if asset["name"] == self.scheme_file:
                    return {
                        "url": self.mirror_url(asset["browser_download_url"]),
                        # 修改为获取asset的更新时间
                        "update_time": asset["updated_at"],
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
        remote_time = datetime.strptime(remote_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        local_time = self.get_local_time()
        
        if local_time and remote_time <= local_time:
            print_success("当前已是最新方案")
            return False  # 没有更新


        # 下载更新
        temp_file = os.path.join(self.custom_dir, "temp_scheme.zip")
        if not self.download_file(remote_info["url"], temp_file):
            return False

        # 校验文件
        target_file = os.path.join(self.custom_dir, self.scheme_file)
        if os.path.exists(target_file) and self.file_compare(temp_file, target_file):
            print_success("文件内容未变化")
            os.remove(temp_file)
            return False

        # 应用更新
        self.apply_update(temp_file, os.path.join(self.custom_dir, self.scheme_file), remote_info)
        self.clean_build()
        print_success("方案更新完成，请在本程序结束后手动重新部署或使用快捷键 Control+Option+` 重新部署​")
        return True  # 成功更新

    def get_local_time(self):
        if not os.path.exists(self.record_file):
            return None
        try:
            with open(self.record_file, 'r') as f:
                data = json.load(f)
                # 读取本地记录的update_time
                return datetime.strptime(data["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except:
            return None

    def file_compare(self, file1, file2):
        hash1 = calculate_sha256(file1)
        hash2 = calculate_sha256(file2)
        return hash1 == hash2

    def apply_update(self, temp, target, info):

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
                "update_time": info["update_time"],  # 使用asset的更新时间
                "apply_time": datetime.now(timezone.utc).isoformat()
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
        release = self.github_api_request(
            f"https://api.github.com/repos/{OWNER}/{REPO}/releases/tags/{self.target_tag}"
        )
        if not release:
            return None
        target_asset = next(
            (a for a in release["assets"] if a["name"] == self.dict_file),
            None
        )
        if not target_asset:
            return None
        return {
            "url": self.mirror_url(target_asset["browser_download_url"]),
            # 使用asset的更新时间
            "update_time": target_asset["updated_at"],
            "tag": release["tag_name"],
            "size": target_asset["size"]
        }
    
    def get_local_time(self):
        if not os.path.exists(self.record_file):
            return None
        try:
            with open(self.record_file, 'r') as f:
                data = json.load(f)
                # 读取本地记录的update_time
                return datetime.strptime(data["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except:
            return None

    def file_compare(self, file1, file2):
        """文件比对"""
        return calculate_sha256(file1) == calculate_sha256(file2)

    def apply_update(self, temp, target, info):
        """ 参数不再需要传递路径，使用实例变量 """
        try:
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
                    "update_time": info["update_time"],  # 使用asset的更新时间
                    "tag": info["tag"],
                    "apply_time": datetime.now(timezone.utc).isoformat()
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
        remote_time = datetime.strptime(remote_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        local_time = self.get_local_time()
        
        if local_time and remote_time <= local_time:
            print_success("当前已是最新词库")
            return False

        # 下载流程
        temp_file = os.path.join(self.custom_dir, "temp_dict.zip")
        target_file = os.path.join(self.custom_dir, self.dict_file)
        if not self.download_file(remote_info["url"], temp_file):
            return False

        # 哈希校验
        if os.path.exists(target_file) and self.file_compare(temp_file, target_file):
            print_success("文件内容未变化")
            os.remove(temp_file)


        try:
            self.apply_update(temp_file, target_file, remote_info)  # 传递三个参数
            print_success("词库更新完成，请在本程序结束后手动重新部署或使用快捷键 Control+Option+` 重新部署")
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
            
        for asset in release.get("assets", []):
            if asset["name"] == self.model_file:
                return {
                    "url": self.mirror_url(asset["browser_download_url"]),
                    # 使用asset的更新时间
                    "update_time": asset["updated_at"],
                    "size": asset["size"]
                }
        return None



    def run(self):
        """执行模型更新主流程"""
        print_header("模型更新流程")
        remote_info = self.check_update()
        if not remote_info:
            print_warning("未找到模型更新信息")
            return False

        # 时间比较（本地记录 vs 远程更新时间）
        remote_time = datetime.strptime(remote_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)  # 修改字段
        local_time = self._get_local_record_time()
        
        if local_time and remote_time <= local_time:
            print_success("当前模型已是最新版本")
            return False

        # 下载到临时文件
        if not self.download_file(remote_info["url"], self.temp_file):
            print_error("模型下载失败")
            return False

        # 无论是否有记录，都检查哈希是否匹配
        hash_matched = self._check_hash_match()
        remote_time = datetime.strptime(remote_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        local_time = self._get_local_record_time()

        # 哈希匹配但记录缺失时的处理
        if hash_matched:
            print_success("模型内容未变化")
            os.remove(self.temp_file)
            # 强制更新记录（解决记录文件丢失的问题）
            if not local_time or remote_time > local_time:
                self._save_update_record(remote_info["update_time"])  # 使用新字段
            return False

        
        # 覆盖目标文件
        try:
            if os.path.exists(self.target_path):
                os.remove(self.target_path)
            os.replace(self.temp_file, self.target_path)  # 原子操作更安全
        except Exception as e:
            print_error(f"模型文件替换失败: {str(e)}")
            return False

        # 保存更新记录
        self._save_update_record(remote_info["update_time"])
        
        # 返回更新成功状态
        print_success("模型更新完成，请在本程序结束后手动重新部署或使用快捷键 Control+Option+` 重新部署")
        return True

    def _get_local_record_time(self):
        if not os.path.exists(self.record_file):
            return None
        try:
            with open(self.record_file, "r") as f:
                data = json.load(f)
                # 读取本地记录的update_time
                return datetime.strptime(data["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except:
            return None

    def _check_hash_match(self):
        """检查临时文件与目标文件哈希是否一致"""
        temp_hash = calculate_sha256(self.temp_file)
        target_hash = calculate_sha256(self.target_path) if os.path.exists(self.target_path) else None
        return temp_hash == target_hash

    def _save_update_record(self, update_time):
        record = {
            "model_name": self.model_file,
            "update_time": update_time,  # 使用传入的更新时间
            "apply_time": datetime.now(timezone.utc).isoformat()
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
            print(f"{INDENT}▪ 词库文件：{settings[5]}")
            print(f"{INDENT}▪ 输入法引擎：{settings[8]}")
        except Exception as e:
            print(f"\n{COLOR['FAIL']}❌ 配置加载失败：{str(e)}{COLOR['ENDC']}")
            sys.exit(1)

        # ========== 自动更新检测（仅在程序启动时执行一次）==========
        update_flag = False  # 标记是否存在更新
        
        # 方案更新检测
        scheme_updater = SchemeUpdater(config_manager)
        scheme_info = scheme_updater.check_update()
        if scheme_info:
            remote_time = datetime.strptime(scheme_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            local_time = scheme_updater.get_local_time()
            if local_time is None or remote_time > local_time:
                china_time = remote_time.astimezone(timezone(timedelta(hours=8))).strftime("%Y-%m-%d %H:%M:%S")
                print(f"\n{COLOR['WARNING']}[!] 方案有更新可用（版本：{scheme_info['tag']}）")
                print(f"{INDENT}发布时间：{china_time}{COLOR['ENDC']}")
                update_flag = True
        # 词库更新检测
        dict_updater = DictUpdater(config_manager)
        dict_info = dict_updater.check_update()
        if dict_info:
            remote_time = datetime.strptime(dict_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            local_time = dict_updater.get_local_time()
            if local_time is None or remote_time > local_time:
                china_time = remote_time.astimezone(timezone(timedelta(hours=8))).strftime("%Y-%m-%d %H:%M:%S")
                print(f"\n{COLOR['WARNING']}[!] 词库有更新可用（版本：{dict_info['tag']}）")
                print(f"{INDENT}发布时间：{china_time}{COLOR['ENDC']}")
                update_flag = True
        # 模型更新检测
        model_updater = ModelUpdater(config_manager)
        model_info = model_updater.check_update()
        if model_info:
            remote_time = datetime.strptime(model_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            local_time = model_updater._get_local_record_time()
            if local_time is None or remote_time > local_time:
                china_time = remote_time.astimezone(timezone(timedelta(hours=8))).strftime("%Y-%m-%d %H:%M:%S")
                print(f"\n{COLOR['WARNING']}[!] 模型有更新可用")
                print(f"{INDENT}发布时间：{china_time}{COLOR['ENDC']}")
                update_flag = True
        # 如果没有更新显示提示
        if not update_flag:
            print(f"\n{COLOR['OKGREEN']}[√] 所有组件均为最新版本{COLOR['ENDC']}")

        # 主菜单循环
        while True:
            # 选择更新类型
            print_header("更新类型选择") 
            print("[1] 词库更新\n[2] 方案更新\n[3] 模型更新\n[4] 全部更新\n[5] 修改配置\n[6] 退出程序")
            choice = input("请输入选择（1-6，单独按回车键默认选择全部更新）: ").strip() or '4'
            
            if choice == '5':
                config_manager.display_config_instructions()
                print("保存后关闭配置文件以继续...")

                # 用.ini文件的默认编辑器打开配置文件
                if os.name == 'posix':
                    subprocess.run(['open', config_manager.config_path])
                print_success("配置文件修改已完成")
                
                # 返回主菜单或退出
                user_choice = input("\n按回车键返回主菜单，或输入其他键退出: ").strip().lower()
                if user_choice == '':
                    continue  # 继续主循环
                else:
                    break
            elif choice == '6':
                break
            else:
                # 执行更新操作
                updated = False
                deployer = None
                if choice == '1':
                    updater = DictUpdater(config_manager)
                    updated = updater.run()
                    deployer = updater
                elif choice == '2':
                    updater = SchemeUpdater(config_manager)
                    updated = updater.run()
                    deployer = updater
                elif choice == '3':
                    updater = ModelUpdater(config_manager)
                    updated = updater.run()
                    deployer = updater
                elif choice == '4':
                    # 全部更新模式
                    deployer = SchemeUpdater(config_manager)
                    scheme_updated = deployer.run()
                    dict_updater = DictUpdater(config_manager)
                    dict_updated = dict_updater.run()
                    model_updater = ModelUpdater(config_manager)
                    model_updated = model_updater.run()
                    updated = scheme_updated or dict_updated or model_updated

                    # 自动退出逻辑
                    print("\n" + COLOR['OKGREEN'] + "[√] 全部更新完成，4秒后自动退出..." + COLOR['ENDC'])
                    time.sleep(4)
                    sys.exit(0)


                # 返回主菜单或退出
                user_input = input("\n按回车键返回主菜单，或输入其他键退出: ")
                if user_input.strip().lower() == '':
                    continue  # 继续主循环
                else:
                    break

        print("\n✨ 升级完毕，欢迎下次使用！")
        time.sleep(2)
        sys.exit(0)
        
    except Exception as e:
        print(f"\n{COLOR['FAIL']}💥 程序异常：{str(e)}{COLOR['ENDC']}")
        sys.exit(1)

if __name__ == "__main__":
    main()


