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
from typing import Tuple, Optional, List, Dict, Union
from tqdm import tqdm

UPDATE_TOOLS_VERSION = "DEFAULT_UPDATE_TOOLS_VERSION_TAG"
# ====================== 全局配置 ======================
# 仓库信息
OWNER = "amzxyz"
REPO = "rime_wanxiang"
# cnb信息
CNB_REPO = "rime-wanxiang"
DICT_TAG = "dict-nightly"
# 模型相关配置
MODEL_REPO = "RIME-LMDG"
MODEL_TAG = "LTS"
MODEL_FILE = "wanxiang-lts-zh-hans.gram"

CNB_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36",
    "Accept-Language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
    "Accept": "application/vnd.cnb.web+json" # 确保返回JSON
}
# Zh词库目录
ZH_DICTS = ZH_DICTS_PRO = "dicts"
SCHEME_MAP = {
    '1': 'moqi',
    '2': 'flypy',
    '3': 'zrm',
    '4': 'tiger',
    '5': 'wubi',
    '6': 'hanxin'
}

# ====================== 系统检测函数 ===========================
def system_check():
    """检查系统类型"""
    if sys.platform == 'win32':
        return 'windows'
    # iOS上a-shell、code app的Python环境sys.pltform也为'darwin'，因此取当前解释器路径进行判断
    elif sys.platform == 'darwin' and sys.executable.find('Code.app') >= 0:
        return 'ios'
    elif sys.platform == 'darwin' and sys.executable == 'python3':
        return 'ios'
    elif sys.platform == 'darwin':
        return 'macos'
    elif sys.platform == 'ios':
        return 'ios'
    else:
        return 'android/linux'

SYSTEM_TYPE = system_check()

# ====================== 界面函数 ======================
BORDER = "=" * 35 if SYSTEM_TYPE == 'ios' else "-" * 60
SUB_BORDER = "-" * 30 if SYSTEM_TYPE == 'ios' else "-" * 55
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
    "ENDC": "\033[0m"
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


# ====================== win注册表路径配置 ======================
if SYSTEM_TYPE == 'windows':
    import winreg

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


# ====================== 配置管理器 ======================
class ConfigManager:
    """配置管理类"""
    def __init__(self):
        self.config_path = self._get_config_path()
        self.config = configparser.ConfigParser()
        self.rime_engine = ''
        self.rime_dir = ''
        self.scheme_type = ''
        self.zh_dicts_dir = ''
        self.reload_flag = False
        self.auto_update = False
        self.change_config = False
        self._ensure_config_exists()

    def detect_installation_paths(self, show=False):
        """自动检测安装路径"""
        detected = {}
        if SYSTEM_TYPE == 'windows':
            for key in REG_PATHS:
                path, name, hive = REG_PATHS[key]
                detected[key] = get_registry_value(path, name, hive)
            
            # 智能路径处理
            if detected['weasel_root'] and detected['server_exe']:
                detected['server_exe'] = os.path.join(detected['weasel_root'], detected['server_exe'])
            else:
                print_error("无法自动检测到 Weasel 根目录或 WeaselServer.exe。")
                print_error("你的小狼毫可能没有安装或配置正确。")
                print_error("正在退出程序...")
                sys.exit(1)

            defaults = {
                'rime_user_dir': os.path.join(os.environ['APPDATA'], 'Rime')
            }
            
            if not detected["rime_user_dir"] or not os.path.exists(detected['rime_user_dir']):
                detected["rime_user_dir"] = defaults["rime_user_dir"]
                if not self.reload_flag and show:
                    print_warning("未检测到小狼毫自定义 RimeUserDir，使用默认路径：" + detected["rime_user_dir"])
            else:
                if not self.reload_flag and show:
                    print_success("检测到小狼毫自定义 RimeUserDir：" + detected["rime_user_dir"])
        elif SYSTEM_TYPE == 'macos':
            # 处理macOS
            if self.config.get('Settings', 'engine') == '鼠须管':
                detected['rime_user_dir'] = os.path.expanduser('~/Library/Rime')
            elif self.config.get('Settings', 'engine') == '小企鹅':
                detected['rime_user_dir'] = os.path.expanduser('~/.local/share/fcitx5/rime')
            else:
                detected['rime_user_dir'] = os.path.expanduser('~/Library/Rime')
        elif SYSTEM_TYPE == 'ios':
            detected['rime_user_dir'] = self.rime_dir
        else:
            current_file_dir = os.path.dirname(os.path.abspath(__file__))
            if os.path.exists(os.path.join(current_file_dir, 'Rime')):
                detected['rime_user_dir'] = os.path.join(current_file_dir, 'Rime')
            elif os.path.exists(os.path.join(current_file_dir, 'rime')):
                detected['rime_user_dir'] = os.path.join(current_file_dir, 'rime')
            else:
                os.makedirs(os.path.join(current_file_dir, 'Rime'), exist_ok=True)
                detected['rime_user_dir'] = os.path.join(current_file_dir, 'Rime')
            
        return detected


    def _check_hamster_path(self) -> bool:
        """检查脚本是否放置在正确的Hamster目录下"""
        file_dir = os.path.dirname(os.path.abspath(__file__))
        hamster_path_names = os.listdir(file_dir)
        if "RIME" in hamster_path_names:
            self.rime_dir = os.path.join(file_dir, 'RIME', 'Rime')
            return True
        elif "Rime" in hamster_path_names:
            self.rime_dir = os.path.join(file_dir, 'Rime')
            return True
        else:
            print_error('请将脚本放置到正确的位置（Hamster目录下）')
            return False
        
    def _select_rime_engine(self) -> None:
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
                # 更新配置文件
                self.config.set('Settings', 'engine', self.rime_engine)
                return
            elif choice == '2':
                self.rime_dir = os.path.expanduser('~/.local/share/fcitx5/rime')
                self.rime_engine = '小企鹅'
                # 更新配置文件
                self.config.set('Settings', 'engine', self.rime_engine)
                return
            else:
                print(f"{INDENT}无效的选择，请重新选择。")

    def _get_config_path(self) -> str:
        """获取配置文件路径"""
        # 检查程序是否是打包后的可执行文件。如果是，sys.frozen 属性会被设置为 True
        if getattr(sys, 'frozen', False):
            # 如果是打包后的可执行文件，获取可执行文件所在的目录
            base_dir = os.path.dirname(sys.executable)
        else:
            # 如果是普通的 Python 脚本，获取当前脚本文件的绝对路径所在的目录
            base_dir = os.path.dirname(os.path.abspath(__file__))
        # 将基础目录和配置文件名 'settings.ini' 拼接成完整的配置文件路径并返回
        return os.path.join(base_dir, 'settings.ini')

    def _ensure_config_exists(self) -> None:
        """确保配置文件存在，如果不存在则创建一个新的配置文件"""
        if SYSTEM_TYPE == 'ios':
            if not self._check_hamster_path():
                return
        if not os.path.exists(self.config_path):
            print_warning("正在创建一个新的配置文件。")
            self._init_empty_config()
            if SYSTEM_TYPE == 'macos':
                self._select_rime_engine()  # mac首次运行选择引擎
            # self._guide_scheme_type_selection()  # 首次运行引导选择方案名称
            # self._guide_scheme_selection()  # 首次运行引导选择方案
            if self._guide_scheme_type_selection() and self._guide_scheme_selection():
                self._write_config() # 写入配置文件
                print_success("配置文件创建成功。")
            else:
                print_error("配置向导失败，请手动配置。")
                exit(1)  # 终止程序执行
            self._show_config_guide()       # 配置引导
        else:
            print_warning(COLOR['YELLOW'] + "配置文件已存在，将加载配置。" + COLOR['ENDC'])
            new_config_items = {
                'auto_update': 'false',
            }
            self._add_new_config_items(new_config_items)
            self._try_load_config()
            self._print_config_info()  # 打印配置信息
            self._confirm_config()  # 确认配置是否符合预期

    def _add_new_config_items(self, new_config_items: Dict[str, str]) -> None:
        """添加或更新配置项"""
        changed = False
        self.config.read(self.config_path, encoding='utf-8')
        for key, value in new_config_items.items():
            if not self.config.has_option('Settings', key):
                print_warning(f"添加缺失的配置项: {key} = {value}")
                self.config.set('Settings', key, value)
                changed = True
        if changed:
            self._write_config()

    def _print_config_info(self) -> None:
        """打印配置信息"""
        print(f"\n{BORDER}")
        print(f"{INDENT}当前配置信息")
        print(f"{BORDER}")
        print(f"{INDENT}▪ 方案版本：{self.config['Settings']['scheme_type']}")
        print(f"{INDENT}▪ 方案文件：{self.config['Settings']['scheme_file']}")
        print(f"{INDENT}▪ 词库文件：{self.config['Settings']['dict_file']}")
        if SYSTEM_TYPE == 'macos':
            print(f"{INDENT}▪ 输入法引擎：{self.config['Settings']['engine']}")
        print(f"{INDENT}▪ 跳过文件目录：{self.config['Settings']['exclude_files']}")
        print(f"{BORDER}")

    def _confirm_config(self) -> None:
        """确认配置是否符合预期"""
        # 如果启用了自动更新，跳过确认步骤
        if self.config.getboolean('Settings', 'auto_update', fallback=False):
            self.auto_update = True
            print_warning("已启用自动更新，跳过配置确认")
            return
        while True:
            choice = input(f"{INDENT}配置是否正确？【Y(y)或回车确认／N(n)重新生成／M(m)修改】: ").strip().lower()
            if choice == 'y' or not choice:
                print_success("配置正确。")
                break
            elif choice == 'n':
                print_warning("请重新配置生成新的配置文件。")
                os.remove(self.config_path)  # 删除配置文件
                self.reload_flag = True
                self._ensure_config_exists()  # 重新创建配置文件
                self.change_config = True
                break
            elif choice == 'm':
                if SYSTEM_TYPE == 'ios':
                    print_warning("iOS平台不支持修改配置文件，请手动编辑 settings.ini 文件。")
                else:
                    if os.name == 'nt':
                        subprocess.run(['notepad.exe', self.config_path], shell=True)
                    else:
                        subprocess.run(['open', self.config_path])
                    print_warning("请在打开的配置文件中手动修改，保存后继续执行。")
                input("按任意键继续...")
                self._try_load_config()  # 再次尝试加载配置
                self._print_config_info()
                self.change_config = True
                break
            else:
                print_error("无效的输入，请重新输入。")

    def _try_load_config(self) -> None:
        """尝试加载配置文件"""
        # 加载并验证配置
        try:
            settings = self.load_config(show=True)
            print(f"\n{COLOR['GREEN']}[√] 配置加载成功{COLOR['ENDC']}")
        except Exception as e:
            print(f"\n{COLOR['FAIL']}❌ 配置加载失败：{str(e)}{COLOR['ENDC']}")
            sys.exit(1)

    def _init_empty_config(self) -> None:
        """创建空配置"""
        self.config['Settings'] = {
            'engine': '',
            'scheme_type': '',
            'scheme_file': '',
            'dict_file': '',
            'use_mirror': 'true',
            'github_token': '',
            'exclude_files': '',
            'auto_update': 'false',

        }
        
    def _write_config(self) -> None:
        """写入配置文件"""
        with open(self.config_path, 'w', encoding='utf-8') as f:
            self.config.write(f)

    def _guide_scheme_type_selection(self) -> bool:
        """首次运行引导选择万象版本"""
        print(f"\n{BORDER}")
        print(f"{INDENT}首次运行方案版本选择向导")
        print(f"{BORDER}")
        print("[1]-万象基础版 [2]-万象增强版（支持各种辅助码）")

        while True:
            choice = input(f"{INDENT}请选择方案版本（1-2）: ").strip()
            if choice == '1':
                self.scheme_type = 'base'
                self.zh_dicts_dir = ZH_DICTS
                scheme_file, dict_file = self.get_actual_filenames('base')
                self.config.set('Settings', 'scheme_type', self.scheme_type)
                self.config.set('Settings', 'scheme_file', scheme_file)
                self.config.set('Settings', 'dict_file', dict_file)
                print_success(f"已选择方案：万象基础版，方案文件: {scheme_file}，词库文件: {dict_file}")
                return True
            elif choice == '2':
                self.scheme_type = 'pro'
                self.zh_dicts_dir = ZH_DICTS_PRO
                self.config.set('Settings', 'scheme_type', self.scheme_type)
                print_success("已选择方案：万象增强版")
                return True
            else:
                print_error("无效的选项，请重新输入")

    def _guide_scheme_selection(self) -> bool:
        """首次运行引导选择方案"""
        if self.scheme_type == 'pro':
            print(f"\n{BORDER}")
            print(f"{INDENT}万象Pro首次运行辅助码选择配置向导")
            print("[1]-墨奇 [2]-小鹤 [3]-自然码")
            print("[4]-虎码 [5]-五笔 [6]-汉心")
        
            while True:
                choice = input("请选择你的辅助码方案（1-7）: ").strip()
                if choice in SCHEME_MAP:
                    scheme_key = SCHEME_MAP[choice]
                    
                    # 立即获取实际文件名
                    scheme_file, dict_file = self.get_actual_filenames(scheme_key)
                    
                    self.config.set('Settings', 'scheme_file', scheme_file)
                    self.config.set('Settings', 'dict_file', dict_file)
                    
                    print_success(f"已选择方案：{scheme_key.upper()}")
                    print(f"方案文件: {scheme_file}")
                    print(f"词库文件: {dict_file}")
                    return True
                print_error("无效的选项，请重新输入")
        else:
            print_success(f"基础版使用方案文件: {self.config.get('Settings', 'scheme_file')} 和词库文件: {self.config.get('Settings', 'dict_file')}")
            return True

            
    def get_actual_filenames(self, scheme_key) -> Tuple[str, str]:
        """
        获取实际文件名（带网络请求）
        Args:
            scheme_key (str): 方案关键字
        Returns:
            Tuple[str, str]: 方案文件名，词库文件名
        """
        try:
            if self.scheme_type == 'base':
                scheme_pattern = f"*base.zip"
                dict_pattern = f"*base*.zip"
            else:
                scheme_pattern = f"*{scheme_key}*fuzhu.zip"
                dict_pattern = f"*{scheme_key}*dicts.zip"
            

            scheme_checker = FileChecker(
                owner=OWNER,
                repo=CNB_REPO if self.config.getboolean('Settings', 'use_mirror') else REPO,
                pattern=scheme_pattern,
                use_mirror=self.config.getboolean('Settings', 'use_mirror')
            )
            dict_checker = FileChecker(
                owner=OWNER,
                repo=CNB_REPO if self.config.getboolean('Settings', 'use_mirror') else REPO,
                pattern=dict_pattern,
                use_mirror=self.config.getboolean('Settings', 'use_mirror'),
                tag=DICT_TAG
            )
            
            # 获取文件名
            scheme_file = scheme_checker.get_latest_file()
            dict_file = dict_checker.get_latest_file()
            print(scheme_file, dict_file)
            
            # 验证文件名是否有效
            if not scheme_file or not dict_file:
                raise ValueError(f"未找到匹配的文件: {scheme_pattern} 或 {dict_pattern}")
            
            return scheme_file, dict_file
            
        except Exception as e:
            print_error(f"无法获取最新文件名: {str(e)}")
            print_error("请检查网络连接，或关闭代理后重试...")
            sys.exit(-1)

    def _show_config_guide(self) -> None:
        """配置引导界面"""
        # 显示第一个路径检测界面
        print(f"\n{BORDER}")
        print(f"{INDENT}自动检测路径结果")
        print(f"{BORDER}")
        
        self.config.read(self.config_path, encoding='utf-8')
        detected = self.detect_installation_paths()
        status_emoji = {True: "✅", False: "❌"}
        for key in detected:
            exists = os.path.exists(detected[key])
            print(f"{INDENT}{key.ljust(15)}: {status_emoji[exists]} {detected[key]}")
        
        print(f"\n{INDENT}生成的配置文件路径: {self.config_path}")
        
        self.display_config_instructions()

        if os.name == 'nt':
            os.startfile(self.config_path)
        elif os.name == 'posix' and SYSTEM_TYPE == 'macos':
            subprocess.Popen(['open', self.config_path])
        else:
            None
        input("\n请按需修改上述路径，保存后按回车键继续...")

    def display_config_instructions(self) -> None:
        """静默显示配置说明"""
        print_header("请检查配置文件路径,需用户修改")
        print("\n▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂")
        print("使用说明：\n")
        
        path_display = [
            ("[engine]", "Mac端选择的输入法引擎", 'engine'),
            ("[scheme_type]", "选择的方案版本", 'scheme_type'),
            ("[scheme_file]", "选择的方案文件名称", 'scheme_file'),
            ("[dict_file]", "关联的词库文件名称", 'dict_file'),
            ("[use_mirror]", "是否使用国内仓库CNB(网址:cnb.cool,默认true)", 'use_mirror'),
            ("[github_token]", "GitHub令牌(可选)", 'github_token'),
            ("[exclude_files]", "更新时需保留的免覆盖文件(默认为空,逗号分隔...格式如下tips_show.txt", 'exclude_files'),
            ("[auto_update]", "是否跳过确认并自动更新(默认false)", 'auto_update'),
        ]
        
        for item in path_display:
            print(f"    {item[0].ljust(25)}{item[1]}")
            print(f"        {self.config['Settings'][item[2]]}\n")
        
        print("▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂")
        

    def load_config(self, 
                    system=SYSTEM_TYPE, 
                    show=False, 
                    first_download=False
                ) -> Tuple[str, str, str, str, bool, str, list]:
        """
        加载配置文件
        Args:
            system (str): 系统类型
            show (bool): 是否显示小狼毫路径说明
            first_download (bool): 是否是第一次下载
        Returns:
            Tuple[str, str, str, str, bool, str, list]: 配置信息
        """
        self.config.read(self.config_path, encoding='utf-8')
        config = {k: v.strip('"') for k, v in self.config['Settings'].items()}
        github_token = config.get('github_token', '')
        
        # 读取排除文件配置
        exclude_files = [
            pattern.strip() 
            for pattern in re.split(r',|，', self.config.get('Settings', 'exclude_files', fallback=''))  # 同时分割中英文逗号
            if pattern.strip()
        ]

        self.scheme_type = config.get('scheme_type', 'pro')
        if self.scheme_type == 'base':
            self.zh_dicts_dir = ZH_DICTS
        else:
            self.zh_dicts_dir = ZH_DICTS_PRO

        # 验证关键路径
        if system == 'windows':
            paths = self.detect_installation_paths(show=show)
            required_paths = {
                '小狼毫服务程序': paths['server_exe'],
                '方案解压目录': paths['rime_user_dir'],
                '词库解压目录': os.path.join(paths['rime_user_dir'], self.zh_dicts_dir)
            }
        elif system == 'macos':
            paths = self.detect_installation_paths()
            required_paths = {
                '方案解压目录': paths['rime_user_dir'],
                '词库解压目录': os.path.join(paths['rime_user_dir'], self.zh_dicts_dir),
            }
        elif system == 'ios':
            required_paths = {
                '方案解压目录': self.rime_dir,
                '词库解压目录': os.path.join(self.rime_dir, self.zh_dicts_dir)
            }
        else:
            paths = self.detect_installation_paths()
            required_paths = {
                '方案解压目录': paths['rime_user_dir'],
                '词库解压目录': os.path.join(paths['rime_user_dir'], self.zh_dicts_dir)
            }

        if first_download:
            missing = [] if os.path.exists(required_paths['方案解压目录']) else [required_paths['方案解压目录']]
        else:
            missing = [path for name, path in required_paths.items() if not os.path.exists(path)]
            if not os.path.exists(required_paths['方案解压目录']):
                print(f"\n{COLOR['FAIL']}关键路径配置错误：{COLOR['ENDC']}")
                for name in missing:
                    print(f"{INDENT}{name}: {required_paths[name]}")
                print(f"\n{INDENT}可能原因：")
                if system == 'windows':
                    print(f"{INDENT}1. 小狼毫输入法未正确安装")
                    print(f"{INDENT}2. 注册表信息被修改")
                    print(f"{INDENT}3. 自定义路径配置错误")
                elif system == 'macos':
                    print(f"{INDENT}1. 鼠须管或小企鹅输入法未正确安装")
                    print(f"{INDENT}2. 自定义路径配置错误")
                elif system == 'ios':
                    print(f"{INDENT}1. 该路径不存在")
                    print(f"{INDENT}2. 没有将该脚本放置在Hamster路径下")
                else:
                    print(f"{INDENT}1. 该路径不存在")
                    print(f"{INDENT}2. 没有将该脚本放置在正确路径下")
                sys.exit(1)
            
        if missing:
            self.ensure_directories(missing)
            
            
        return (
            config['engine'],
            config['scheme_type'],
            config['scheme_file'],
            config['dict_file'],
            self.config.getboolean('Settings', 'use_mirror'),
            github_token,
            exclude_files,
        )
    
    def ensure_directories(self, dirs: List) -> None:
        """目录保障系统"""
        for dir in dirs:
            os.makedirs(dir, exist_ok=True)


class FileChecker:
    def __init__(self, owner, repo, pattern, use_mirror, tag=None):
        self.owner = owner
        self.repo = repo
        self.pattern_regex = re.compile(pattern.replace('*', '.*'))
        self.tag = tag
        self.use_mirror = use_mirror

    def get_latest_file(self) -> Optional[str]:
        """获取匹配模式的最新文件"""
        if self.use_mirror:
            releases = self._get_cnb_releases()
            for asset in releases.get("assets", []):
                if self.pattern_regex.match(asset['name']):
                    return asset['name']
        else:
            releases = self._get_releases()
            for release in releases:
                for asset in release.get("assets", []):
                    if self.pattern_regex.match(asset['name']):
                        return asset['name']
        return None

    def _get_releases(self) -> List:
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
    
    def _get_cnb_releases(self) -> Dict:
        headers = CNB_HEADERS
        url = f'https://cnb.cool/{self.owner}/{self.repo}/-/releases'
        response = requests.get(url=url, headers=headers)
        if response.status_code == 200:
            releases_all = response.json()
            releases_list = releases_all['releases']
            for release in releases_list:
                if self.tag:
                    if "词库" in release.get("title"):
                        return release # 词库
                if "万象拼音输入方案" in release.get("title"):
                    return release # 方案
        return {}
        

# ====================== 更新基类 ======================
class UpdateHandler:
    """更新系统核心基类"""
    def __init__(self, config_manager):
        """
        初始化更新处理器
        Args:
            config_manager (ConfigManager): 配置管理器
            first_download (bool): 是否是第一次下载，用于传递给load_config方法，默认False，需手动设置为True
        """
        self.config_manager = config_manager
        (
            self.engine,
            self.scheme_type,
            self.scheme_file,
            self.dict_file,
            self.use_mirror,
            self.github_token,
            self.exclude_files
        ) = config_manager.load_config(show=False)
        (
            self.custom_dir,
            self.extract_path,
            self.dict_extract_path,
            self.weasel_server
        ) = self.get_all_dir()
        os.makedirs(self.custom_dir, exist_ok=True)
        self.update_info = None

    def has_update(self) -> bool:
        """检查是否有更新可用"""
        # 如果没有更新信息或本地没有获取本地时间
        if not self.update_info:
            return False
        
        if self.config_manager.change_config and not isinstance(self, ModelUpdater):
            return True
        remote_time = datetime.strptime(self.update_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        local_time = self.get_local_time()
        
        # 如果本地没有时间记录或有新更新
        return not local_time or remote_time > local_time
    
    def get_local_time(self) -> Optional[datetime]:
        """获取本地记录的更新时间"""
        return None

    def get_all_dir(self) -> Tuple[str, str, str, str]:
        """获取所有目录"""
        rime_user_dir = self.config_manager.detect_installation_paths().get('rime_user_dir', '')
        server = self.config_manager.detect_installation_paths().get('server_exe', '')
        zh_dicts_dir = self.config_manager.zh_dicts_dir
        return (
            os.path.join(rime_user_dir, 'UpdateCache'), 
            rime_user_dir, 
            os.path.join(rime_user_dir, zh_dicts_dir),
            server
        )
    
    def get_old_file_list(self, old_exists_temp_zip: str, new_temp_zip: str, is_dict: bool = False) -> Tuple[List[str], List[str]]:
        """
        获取旧版本压缩包中的文件路径（用于清理）
        
        Args:
            old_exists_temp_zip: 旧版本 zip 压缩包路径
            new_temp_zip: 新版本 zip 压缩包路径
            is_dict: 是否是词库（词库路径不同，处理略有区别）
    
        Returns:
            Tuple:
                - 所有应删除的旧文件（非排除项）
                - 新版本中不再使用的文件或目录路径
        """
        def is_file(path): return os.path.isfile(path)
        def is_dir(path): return os.path.isdir(path)
    
        whole_old_file_paths: List[str] = []
        should_delete_paths: List[str] = []
        
        old_members = new_members = []
        try:
            with zipfile.ZipFile(old_exists_temp_zip, 'r') as old_zip:
                for i in old_zip.namelist():
                    try:
                        old_members.append(i.encode('cp437').decode('utf-8'))
                    except:
                        old_members.append(i)
    
            if new_temp_zip and os.path.isfile(new_temp_zip):
                with zipfile.ZipFile(new_temp_zip, 'r') as new_zip:
                    for i in new_zip.namelist():
                        try:
                            new_members.append(i.encode('cp437').decode('utf-8'))
                        except:
                            new_members.append(i)
    
            # 处理词库情况下的路径差异
            if is_dict:
                # 去除可能有的目录前缀
                new_members = [m.split('/')[-1] for m in new_members if m.split('/')[-1]]
                old_members = [m.split('/')[-1] for m in old_members if m.split('/')[-1]]
    
            # 新版本中不再包含的旧文件
            should_delete_members = [m for m in old_members if m not in new_members]
    
            extract_path = self.dict_extract_path if is_dict else self.extract_path
    
            # 所有旧文件路径
            whole_old_file_paths = [
                path for path in (os.path.join(extract_path, name) for name in old_members)
                if is_file(path)
            ]
            
            # 判断函数根据 is_dict 选择
            check_func = is_file if is_dict else is_dir
            
            # 新版本中不再使用的文件/目录路径
            should_delete_paths = [
                path for path in (os.path.join(extract_path, name) for name in should_delete_members)
                if check_func(path)
            ]

            # 排除指定不删除文件
            if getattr(self, "exclude_files", []):
                excluded = []
                for ex in self.exclude_files:
                    excluded.extend([f for f in whole_old_file_paths if ex in f])
                    
                excluded = set(excluded)  # 去重
                if excluded:
                    print("以下为排除文件不删除：", ", ".join(excluded))
                    whole_old_file_paths = [f for f in whole_old_file_paths if f not in excluded]
    
        except Exception as e:
            print_warning(f"无法获取需要清理的旧文件或目录：{e}")
    
        return whole_old_file_paths, should_delete_paths

            
    def _delete_old_files(self, old_file_list: List, old_dir_list: List) -> None:
        """
        获取旧的压缩包文件
        Args:
            old_file_list: 获取到的需要删除的文件列表
        """
        if hasattr(self, 'terminate_processes'):
            # 终止进程
            self.terminate_processes()
        # 移除不再使用的文件夹
        for file_dir in old_dir_list:
            if os.path.exists(file_dir):
                shutil.rmtree(file_dir)
        # 移除旧版本文件
        for file in old_file_list:
            if os.path.exists(file):
                os.remove(file)

        
    
    def save_record(self, record_file: str, property_type: str, property_name: str, info: dict) -> None:
        """
        保存更新记录
        Args:
            record_file: 保存路径
            property_type: 类型：方案、词库、模型
            property_name: 名称：写入文件的方案、词库、模型名称（来自GitHub）
            info: 保存的信息
        """
        # 保存记录
        with open(record_file, 'w') as f:
            json.dump({
                property_type: property_name,
                "update_time": info["update_time"],
                "tag": info.get("tag", ""),
                "apply_time": datetime.now(timezone.utc).isoformat(),
                "sha256": info.get("sha256", ""),
                "cnb_id": info.get("id", "")
            }, f)
        

    def remote_api_request(self, url, use_mirror=False, output_json=True) -> Optional[Union[Dict,requests.Response]]:
        """
        带令牌认证的API请求
        Args:
            url (str): API请求的URL
        Returns:
            dict: API响应的JSON数据
        """
        if use_mirror:
            headers = CNB_HEADERS
        else:
            headers = {"User-Agent": "RIME-Updater/1.0"}
            if self.github_token:
                headers["Authorization"] = f"Bearer {self.github_token}"
        
        max_retries = 2
        for attempt in range(max_retries + 1):
            try:
                response = requests.get(url, headers=headers)
                response.raise_for_status()
                if output_json:
                    if use_mirror:
                        releases_list = response.json()['releases']
                        return releases_list
                    return response.json()
                else:
                    return response
                
            except requests.HTTPError as e:
                if e.response.status_code == 401:
                    print_error("GitHub令牌无效或无权限")
                elif e.response.status_code == 403:
                    print_error("权限不足或触发次级速率限制")
                else:
                    print_error(f"HTTP错误: {e.response.status_code}")
                return None
            except requests.ConnectionError:
                print_error("网络连接失败")
                if attempt < max_retries:
                    time.sleep(5)
                    continue
                return None
            except requests.RequestException as e:
                print_error(f"请求异常: {str(e)}")
                return None
        
        return None


    def download_file(self, url, save_path, is_continue) -> bool:
        """
        带进度显示的稳健下载
        Args:
            url (str): 下载链接
            save_path (str): 保存路径
            is_continue (bool): 是否断点续传
        """
        try:
            # 统一提示使用cnb或GitHub状态
            if self.use_mirror:
                print(f"{COLOR['OKBLUE']}[i] 正在使用 https://cnb.cool 下载{COLOR['ENDC']}")
                # print(f"{COLOR['WARNING']}注意: 如果使用代理，请确保关闭后再尝试下载{COLOR['ENDC']}")
            else:
                print(f"{COLOR['OKCYAN']}[i] 正在使用 https://github.com 下载{COLOR['ENDC']}")

            headers = {}
            # 获取已下载进度
            if is_continue:
                downloaded = os.path.getsize(save_path)
            else:
                downloaded = 0
            headers['Range'] = f'bytes={downloaded}-'
            
            response = requests.get(url, headers=headers, stream=True)
            total_size = int(response.headers.get('content-length', 0)) + downloaded
            block_size = 8192
            
            # 使用 tqdm 包装响应内容的迭代器
            with open(save_path, 'ab') as f:
                # tqdm 的 total 参数设置为文件总大小，单位为字节
                with tqdm(total=total_size, initial=downloaded, unit='B', unit_scale=True, desc="下载中") as pbar:
                    for data in response.iter_content(block_size): 
                        f.write(data)
                        pbar.update(len(data))  # 更新进度条
            return True
        except Exception as e:
            print_error(f"下载失败: {str(e)}")
            return False

    def extract_zip(self, zip_path, target_dir, is_dict=False) -> bool:
        """
        智能解压系统(支持排除文件)
        Args:
            zip_path (str): 压缩文件路径
            target_dir (str): 解压目标路径
            is_dict (bool): 是否为词库文件(决定解压方式)
        """
        def get_common_base_dir(members):
            if not members:
                return ""
            try:
                common_prefix = os.path.commonprefix(members)
                if common_prefix:
                    return os.path.dirname(common_prefix) + '/'
                return ""
            except:
                return ""

        try:
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                exclude_patterns = self.exclude_files  # 获取排除模式
                
                members = []
                info_map = {}  # 解码后名字 → ZipInfo 映射
    
                for info in zip_ref.infolist():
                    try:
                        decoded_name = info.filename.encode('cp437').decode('utf-8')
                    except:
                        decoded_name = info.filename
    
                    if info.is_dir():
                        continue
    
                    members.append(decoded_name)
                    info_map[decoded_name] = info
    
                # 计算实际需要解压的文件数量
                valid_members = []
                for member in members:
                    # 标准化路径格式
                    normalized_path = os.path.normpath(member.replace('/', os.sep))
                    file_name = os.path.basename(normalized_path)
                    # 检查排除规则
                    exclude = any(
                        fnmatch.fnmatch(normalized_path, pattern) or 
                        fnmatch.fnmatch(file_name, pattern)
                        for pattern in exclude_patterns
                    )
                    if not exclude:
                        valid_members.append(member)
                    else:
                        print_warning(f"跳过排除文件: {normalized_path}")
    
                # 使用有效文件数量作为进度条的总数
                with tqdm(total=len(valid_members), desc="解压中") as pbar:
                    for member in valid_members:
                        # 计算相对路径
                        if is_dict:
                            base_dir = get_common_base_dir(valid_members)
                            if base_dir and member.startswith(base_dir):
                                relative_path = member[len(base_dir):]
                            else:
                                relative_path = member
                        else:
                            base_dir = get_common_base_dir(valid_members)
                            if base_dir and member.startswith(base_dir):
                                relative_path = member[len(base_dir):]
                            else:
                                relative_path = member
    
                        # 标准化路径
                        normalized_path = os.path.normpath(relative_path.replace('/', os.sep))
                        target_path = os.path.join(target_dir, normalized_path)
                        os.makedirs(os.path.dirname(target_path), exist_ok=True)
                        info = info_map[member]
                        with zip_ref.open(info) as src, open(target_path, 'wb') as dst:
                            dst.write(src.read())
                        pbar.update(1)  # 更新进度条
    
            return True
        except zipfile.BadZipFile:
            print_error("ZIP文件损坏")
            return False
        except Exception as e:
            print_error(f"解压失败: {str(e)}")
            return False


    if SYSTEM_TYPE == 'windows':
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
                time.sleep(0.5)
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
                    # capture_output=True,
                    # text=True,
                    # creationflags=subprocess.CREATE_NO_WINDOW
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    creationflags=subprocess.CREATE_NO_WINDOW
                )
                
                if result.returncode != 0:
                    raise Exception(f"部署失败: {result.stderr.strip()}")
                    
                # print_success("部署成功完成")
                return True
            except Exception as e:
                print_error(f"部署失败: {str(e)}")
                return False
    
    if SYSTEM_TYPE == 'macos':
        def deploy_for_mac(self) -> bool:
            """macOS自动部署"""
            if self.engine == '鼠须管':
                executable = r"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
                cmd = ["--reload"]
            else:
                executable = r"/Library/Input Methods/Fcitx5.app/Contents/bin/fcitx5-curl"
                cmd = ["/config/addon/rime/deploy", "-X", "POST", "-d", "{}"]

            if os.path.exists(executable):
                print_warning("即将进行自动部署，请查看通知中心确认部署")
                time.sleep(2)
                try:
                    subprocess.run([executable] + cmd, check=True, capture_output=True, text=True)
                    print_success("已执行自动部署")
                    return True
                except subprocess.CalledProcessError as e:
                    print_error("自动部署失败：{e}，请手动部署")
                    return False
            else:
                print_error("找不到可执行文件：{executable}")
                return False


# ====================== 组合更新器 ======================
class CombinedUpdater:
    """组合更新处理器 - 同时检查方案和词库更新"""
    def __init__(self, config_manager):
        self.config_manager = config_manager
        # 初始化子更新器
        self.scheme_updater = SchemeUpdater(config_manager)
        self.dict_updater = DictUpdater(config_manager)
        self.model_updater = ModelUpdater(config_manager)
        self.script_updater = ScriptUpdater(config_manager)
        # 存储共享的releases数据
        self.shared_releases = None
        # 文件名重试计数器
        self.filename_retry_count: int = 0
    def fetch_all_updates(self) -> None:
        """获取所有更新信息"""
        url = f"https://api.github.com/repos/{OWNER}/{REPO}/releases"
        use_mirror = self.config_manager.config.getboolean('Settings', 'use_mirror', fallback=False)
        if use_mirror:
            url = f"https://cnb.cool/{OWNER}/{CNB_REPO}/-/releases"
        self.shared_releases = self.scheme_updater.remote_api_request(
            url = url,
            use_mirror = use_mirror
        )
        # 使用共享的releases数据检查方案和词库更新
        self.scheme_updater.update_info = self._extract_scheme_update()
        self.dict_updater.update_info = self._extract_dict_update()
        # 如果方案或词库找不到更新，自动更新文件名
        if not self.scheme_updater.update_info or not self.dict_updater.update_info:
            self.refresh_filenames()
        # 模型更新独立检查
        self.model_updater.update_info = self.model_updater.check_update()
        # 脚本更新独立检查
        self.script_updater.update_info = self.script_updater.check_update()

    def refresh_filenames(self) -> None:
        """自动更新文件名并刷新配置"""
        if self.filename_retry_count >= 2:  # 最多重试2次
            print_warning("文件名自动更新已达最大重试次数")
            return
        print_subheader("检测到文件名变更，自动更新配置...")
        self.filename_retry_count += 1
        # 获取当前方案类型和key
        scheme_type = self.config_manager.scheme_type
        scheme_key = self.extract_scheme_key()
        # 获取新的实际文件名
        try:
            new_scheme_file, new_dict_file = self.config_manager.get_actual_filenames(scheme_key)
            
            # 更新配置
            self.config_manager.config.set('Settings', 'scheme_file', new_scheme_file)
            self.config_manager.config.set('Settings', 'dict_file', new_dict_file)
            self.config_manager._write_config()
            print_success(f"方案文件更新为: {new_scheme_file}")
            print_success(f"词库文件更新为: {new_dict_file}")
            # 刷新更新器实例
            self.scheme_updater = SchemeUpdater(self.config_manager)
            self.dict_updater = DictUpdater(self.config_manager)
            # 重新获取更新信息
            self.scheme_updater.update_info = self._extract_scheme_update()
            self.dict_updater.update_info = self._extract_dict_update()
        except Exception as e:
            print_error(f"文件名自动更新失败: {str(e)}")

    def extract_scheme_key(self) -> str:
        """从当前方案文件名中提取方案key"""
        try:
            current_file = self.config_manager.config.get('Settings', 'scheme_file')
        except configparser.NoOptionError:
            current_file = ""
        if self.config_manager.scheme_type == 'base':
            return 'base'
        # 增强版从文件名提取key
        for key in SCHEME_MAP.values():
            if key in current_file:
                return key
        return list(SCHEME_MAP.values())[0]

    def _extract_scheme_update(self) -> Optional[Dict]:
        """从仓库数据中提取方案更新"""
        if not self.shared_releases:
            return None
            
        for release in self.shared_releases:
            for asset in release.get("assets", []):
                if asset["name"] == self.scheme_updater.scheme_file:
                    update_description = release.get("body", "无更新说明")
                    return {
                        "scheme_name" : asset["name"],
                        "url": asset.get("browser_download_url") or "https://cnb.cool" + asset.get("path"),
                        "update_time": asset.get("updated_at"),
                        "tag": release.get("tag_name") or release.get("tag_ref").split('/')[-1], # 前面是GitHub上tag内容，后面是cnb上tag内容，两者都是版本信息
                        "description": update_description,
                        "sha256": asset.get("digest").split(':')[-1] if asset.get("digest","") else "", # 仅GitHub
                        "id": asset.get("id", "")                                               # 仅cnb
                    }
        return None
    
    def _extract_dict_update(self) -> Optional[Dict]:
        """从仓库数据中提取词库更新"""
        if not self.shared_releases:
            return None
            
        for release in self.shared_releases:
            for asset in release.get("assets", []):
                if asset["name"] == self.dict_updater.dict_file:
                    return {
                        "dict_name" : asset["name"],
                        "url": asset.get("browser_download_url") or "https://cnb.cool" + asset.get("path"),
                        "update_time": asset.get("updated_at"),
                        "tag": release.get("tag_name") or release.get("tag_ref").split('/')[-1], # 前面是GitHub上tag内容，后面是cnb上tag内容，两者都是版本信息,
                        "sha256": asset.get("digest").split(':')[-1] if asset.get("digest","") else "", # 仅GitHub
                        "id": asset.get("id", "")                                               # 仅cnb
                    }
        return None


# ====================== 方案更新 ======================
class SchemeUpdater(UpdateHandler):
    """方案更新处理器"""
    def __init__(self, config_manager):
        super().__init__(config_manager)
        self.record_file = os.path.join(self.custom_dir, "scheme_record.json")
        

    def run(self) -> int:
        """
        return:
            -1: 更新失败
            0: 已经是最新/无可用更新
            1: 更新成功
        """
        print_header("方案更新流程")
        # 使用缓存信息而不是重复API调用
        remote_info = self.update_info
        
        target_file = os.path.join(self.custom_dir, self.scheme_file)
        # 校验本地文件和远端文件sha256
        if remote_info['sha256']:
            if os.path.exists(target_file) and self.file_compare(remote_info['sha256'], target_file):
                print_success("文件内容未变化，将更新本地保存的记录")
                self.save_record(self.record_file, "scheme_file", self.scheme_file, remote_info)
                return 0
        
        # 下载更新
        _suffix = remote_info['sha256'] or remote_info['id']
        temp_file = os.path.join(self.custom_dir, f"temp_scheme_{_suffix}.zip")
        if os.path.exists(temp_file):
            is_continue = True
        else:
            is_continue = False
            for old_should_drop in fnmatch.filter(os.listdir(self.custom_dir), "temp_scheme*.zip"):
                os.remove(os.path.join(self.custom_dir, old_should_drop))
        if not self.download_file(remote_info["url"], temp_file, is_continue):
            return -1
            
        # 方案变更时清除旧文件
        if not self.clean_old_schema():
            # 获取上次下载的压缩包的内容
            old_files, old_dirs = self.get_old_file_list(target_file, temp_file)
            if old_files or old_dirs:
                self._delete_old_files(old_files, old_dirs)
                print_warning("已移除上个版本的方案文件及残余文件夹")


        # 应用更新
        self.apply_update(temp_file, target_file, remote_info)
        # self.clean_build()
        print_success("方案更新完成")
        return 1

    def get_local_time(self) -> Optional[datetime]:
        if not os.path.exists(self.record_file):
            return None
        try:
            with open(self.record_file, 'r') as f:
                data = json.load(f)
                # 读取本地记录的update_time
                return datetime.strptime(data["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except:
            return None

    def file_compare(self, remote_hash, file2) -> bool:
        hash1 = remote_hash
        hash2 = calculate_sha256(file2)
        return hash1 == hash2

    def apply_update(self, temp, target, info) -> None:
        """
        应用更新（替换文件）
        Args:
            temp (str): 临时文件路径
            target (str): 目标文件路径
            info (dict): 更新信息
        """
        if hasattr(self, 'terminate_processes'):
            # 终止进程
            self.terminate_processes()
        # 解压文件
        if not self.extract_zip(temp, self.extract_path):
            raise Exception("解压失败")
        # 解压成功重命名文件
        if os.path.exists(target):
            os.remove(target)
        os.rename(temp, target)
        # 保存记录
        self.save_record(self.record_file, "scheme_file", self.scheme_file, info)

    def clean_build(self) -> None:
        """清理build目录"""
        build_dir = os.path.join(self.extract_path, "build")
        if os.path.exists(build_dir):
            shutil.rmtree(build_dir)
            print_success("已清理build目录")
            
    def clean_old_schema(self) -> bool:
        """当变更所使用的方案时，删除旧文件"""
        cleaned = False
        for file in os.listdir(self.custom_dir):
            if 'rime-wanxiang' in file and file != self.scheme_file:
                old_schema_files, old_schema_dirs = self.get_old_file_list(os.path.join(self.custom_dir, file), '')
                self._delete_old_files(old_schema_files, old_schema_dirs)
                print_warning("已删除旧方案文件")
                os.remove(os.path.join(self.custom_dir, file))
                print_warning("已移除旧方案zip文件")
                cleaned = True
        return cleaned
            

# ====================== 词库更新 ======================
class DictUpdater(UpdateHandler):
    """词库更新处理器"""
    def __init__(self, config_manager):
        super().__init__(config_manager)
        self.target_tag = DICT_TAG
        self.record_file = os.path.join(self.custom_dir, "dict_record.json")

    def get_local_time(self) -> Optional[datetime]:
        """获取本地记录的更新时间"""
        if not os.path.exists(self.record_file):
            return None
        try:
            with open(self.record_file, 'r') as f:
                data = json.load(f)
                # 读取本地记录的update_time
                return datetime.strptime(data["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except:
            return None

    def file_compare(self, remote_hash, file2) -> bool:
        """sha256对比"""
        return remote_hash == calculate_sha256(file2)

    def apply_update(self, temp, target, info) -> None:
        """应用更新（替换文件）， 参数不再需要传递路径，使用实例变量 """
        try:
            # 终止进程
            if hasattr(self, 'terminate_processes'):
                self.terminate_processes()
            # 替换文件（使用明确的实例变量）
            if os.path.exists(target):
                os.remove(target)
            os.rename(temp, target)
            # 解压到配置目录
            if not self.extract_zip(
                target,
                self.dict_extract_path,
                is_dict=True
            ):
                raise Exception("解压失败")
        
            # 保存记录
            self.save_record(self.record_file, "dict_file", self.dict_file, info)
        except Exception as e:
            # 清理残留文件
            if os.path.exists(temp):
                os.remove(temp)
            raise

    def run(self) -> int:
        """
        执行更新
        return:
            -1: 更新失败
            0: 已经是最新/无可用更新
            1: 更新成功
        """
        print_header("词库更新流程")
        # 使用缓存信息而不是重复API调用
        remote_info = self.update_info
        
        target_file = os.path.join(self.custom_dir, self.dict_file)
        # 校验本地文件和远端文件sha256
        if remote_info['sha256']:
            if os.path.exists(target_file) and self.file_compare(remote_info['sha256'], target_file):
                print_success("文件内容未变化，将更新本地保存的记录")
                self.save_record(self.record_file, "dict_file", self.dict_file, remote_info)
                return 0

        # 下载流程
        _suffix = remote_info['sha256'] or remote_info['id']
        temp_file = os.path.join(self.custom_dir, f"temp_dict_{_suffix}.zip")
        if os.path.exists(temp_file):
            is_continue = True
        else:
            is_continue = False
            for old_should_drop in fnmatch.filter(os.listdir(self.custom_dir), "temp_dict*.zip"):
                os.remove(os.path.join(self.custom_dir, old_should_drop))
        if not self.download_file(remote_info["url"], temp_file, is_continue):
            return -1
        
        # 方案变更时清除旧文件
        if not self.clean_old_dict():
            # 获取上次下载的压缩包的内容
            old_files, _ = self.get_old_file_list(target_file, temp_file, is_dict=True)
            if old_files:
                self._delete_old_files(old_files, _)
                print_warning("已移除上个版本的词库文件")
        
        try:
            self.apply_update(temp_file, target_file, remote_info)  # 传递三个参数
            print_success("词库更新完成")
            return 1
        except Exception as e:
            print_error(f"更新失败: {str(e)}")
            # 回滚临时文件
            if os.path.exists(temp_file):
                os.remove(temp_file)
            return -1
            
    def clean_old_dict(self) -> None:
        """当变更所使用的方案时，删除旧文件"""
        cleaned = False
        for file in os.listdir(self.custom_dir):
            if 'dicts.zip' in file and file != self.dict_file:
                old_dict_files, _ = self.get_old_file_list(os.path.join(self.custom_dir, file), '', is_dict=True)
                self._delete_old_files(old_dict_files, _)
                print_warning("已删除旧词库文件")
                os.remove(os.path.join(self.custom_dir, file))
                print_warning("已移除旧词库zip文件")
                cleaned = True
        return cleaned

# ====================== 模型更新 ======================
class ModelUpdater(UpdateHandler):
    """模型更新处理器"""
    def __init__(self, config_manager):
        super().__init__(config_manager)
        self.record_file = os.path.join(self.custom_dir, "model_record.json")
        # 模型固定配置
        self.model_file = "wanxiang-lts-zh-hans.gram"
        self.target_path = os.path.join(self.extract_path, self.model_file) 

    def check_update(self) -> Optional[Dict]:
        """检查模型更新"""
        url = f"https://api.github.com/repos/{OWNER}/{MODEL_REPO}/releases/tags/{MODEL_TAG}"
        use_mirror = self.config_manager.config.getboolean('Settings', 'use_mirror', fallback=False)
        if use_mirror:
            url = f"https://cnb.cool/{OWNER}/{CNB_REPO}/-/releases"
        release = self.remote_api_request(
            url = url,
            use_mirror = use_mirror
        )
        if not release:
            return None
            
        release = release[-1] if isinstance(release, list) else release
        for asset in release.get("assets", []):
            if asset["name"] == self.model_file:
                return {
                    "url": asset.get("browser_download_url") or "https://cnb.cool" + asset.get("path"),
                    # 使用asset的更新时间
                    "update_time": asset.get("updated_at"),
                    "size": asset.get("size") or asset.get("sizeInByte"),
                    "sha256": asset.get("digest").split(':')[-1] if asset.get("digest") else "",
                    "id": asset.get("id")
                }
        return None

    def run(self) -> int:
        """
        执行模型更新主流程
        return:
            -1: 更新失败
            0: 已经是最新/无可用更新
            1: 更新成功
        """
        print_header("模型更新流程")
        # 使用缓存信息而不是重复API调用
        remote_info = self.update_info

        # 无论是否有记录，都检查哈希是否匹配
        hash_matched = self._check_hash_match(remote_info)

        # 哈希匹配但记录缺失时的处理
        if hash_matched:
            print_success("模型内容未变化，将更新本地保存的记录")
            self.save_record(self.record_file, "model_name", self.model_file, remote_info)
            return 0

        # 下载到临时文件
        _suffix = remote_info['sha256'] or remote_info['id']
        temp_file = os.path.join(self.custom_dir, f"{self.model_file}_{_suffix}.tmp") 
        if os.path.exists(temp_file):
            is_continue = True
        else:
            is_continue = False
            for old_should_drop in fnmatch.filter(os.listdir(self.custom_dir), f"{self.model_file}*.tmp"):
                os.remove(os.path.join(self.custom_dir, old_should_drop))
        if not self.download_file(remote_info["url"], temp_file, is_continue):
            print_error("模型下载失败")
            return -1

        # 停止服务再覆盖
        if hasattr(self, 'terminate_processes'):
            self.terminate_processes()  # 复用终止进程逻辑
        
        # 覆盖目标文件
        try:
            if os.path.exists(self.target_path):
                os.remove(self.target_path)
            os.replace(temp_file, self.target_path)  # 原子操作更安全
            self.save_record(self.record_file, "model_name", self.model_file, remote_info)
        except Exception as e:
            print_error(f"模型文件替换失败: {str(e)}")
            return -1
        
        # 返回更新成功状态
        print_success("模型更新完成")
        return 1

    def get_local_time(self) -> Optional[datetime]:
        if not os.path.exists(self.record_file):
            return None
        try:
            with open(self.record_file, "r") as f:
                data = json.load(f)
                # 读取本地记录的update_time
                return datetime.strptime(data["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except:
            return None

    def _check_hash_match(self, remote_info) -> bool:
        """检查临时文件与目标文件哈希是否一致"""
        temp_hash = remote_info['sha256']
        if temp_hash:
            target_hash = calculate_sha256(self.target_path) if os.path.exists(self.target_path) else None
            return temp_hash == target_hash
        return False


class ScriptUpdater(UpdateHandler):
    def __init__(self, config_manager):
        super().__init__(config_manager)
        self.script_path = os.path.abspath(__file__)

    def check_update(self) -> Optional[Dict]:
        releases = self.remote_api_request("https://api.github.com/repos/rimeinn/rime-wanxiang-update-tools/releases")
        if not releases:
            return None
        
        remote_version = releases[0].get("tag_name", "DEFAULT")
        if not self.compare_version(UPDATE_TOOLS_VERSION, remote_version):
            return None
        update_info = releases[0].get("body", "无更新说明")
        for asset in releases[0].get("assets", []):
            if asset["name"] == 'rime-wanxiang-update-win-mac-ios-android.py':
                return {
                    "url": asset["browser_download_url"],
                    "update_time": datetime.strptime(asset["updated_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).strftime('%Y-%m-%d %H:%M:%S'),
                    "tag": remote_version,
                    "description": update_info
                }
            
    def update_script(self, url: str) -> bool:
        """更新脚本"""
        res = self.remote_api_request(url=url, output_json=False)
        if res.status_code == 200:
            with open(self.script_path, 'wb') as f:
                f.write(res.content)
            print_success("脚本更新成功，请重新运行脚本（iOS用户请退出当前软件重新启动）")
            return True
        else:
            print_error("脚本更新失败，请检查网络连接或手动下载最新脚本")
            return False
        
    def compare_version(self, local_version: str, remote_version: str) -> bool:
        if not local_version.startswith('v'):
            return False
        if local_version != remote_version:
            return True
        return False
    
    def run(self):
        remote_info = self.update_info
        if not remote_info:
            print_warning("未找到脚本更新信息")
            return False
        
        remote_version = remote_info.get("tag", "DEFAULT")
        user_choose = input(f"\n{COLOR['WARNING']}[!] 检测到新版本更新（当前版本：{UPDATE_TOOLS_VERSION}，新版本：{remote_version}），是否更新？(y/n): {COLOR['ENDC']}")
        if user_choose.lower() == 'y':
            print_header("正在更新脚本，请勿进行其他操作...")
            if self.update_script(remote_info["url"]):
                sys.exit(0)
        else:
            return False

# ====================== 工具函数 ======================
def calculate_sha256(file_path) -> Optional[str]:
    """
    计算文件SHA256值
    Args:
        file_path (str): 文件路径
    Returns:
        str: SHA256值
    """
    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except Exception as e:
        print_error(f"计算哈希失败: {str(e)}")
        return None
    
def print_update_status(scheme_updater, dict_updater, model_updater, script_updater) -> None:
    """打印更新状态信息"""
    # 检查哪些组件有更新
    has_script_update = script_updater.update_info
    has_scheme_update = scheme_updater.update_info and scheme_updater.has_update()
    has_dict_update = dict_updater.update_info and dict_updater.has_update()
    has_model_update = model_updater.update_info and model_updater.has_update()
    
    # 脚本更新提示
    if has_script_update:
        print(f"\n{COLOR['WARNING']}==== 脚本更新可用 ===={COLOR['ENDC']}")
        print(f"版本: {has_script_update['tag']}")
        print(f"发布时间: {has_script_update['update_time']}")

    # 方案更新提示(仅当有更新时显示)
    if has_scheme_update:
        scheme_update_info = scheme_updater.update_info
        remote_time = datetime.strptime(scheme_update_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        scheme_local = remote_time.astimezone(timezone(timedelta(hours=8))).strftime("%Y-%m-%d %H:%M:%S")
        
        print(f"\n{COLOR['WARNING']}==== 方案更新可用 ===={COLOR['ENDC']}")
        print(f"{COLOR['WARNING']}版本: {scheme_update_info.get('tag', '未知版本')}{COLOR['ENDC']}")
        print(f"发布时间: {scheme_local}")
        
        raw_description = scheme_update_info.get('description', '无更新说明')

        try:
            update_cache_dir = scheme_updater.custom_dir
            os.makedirs(update_cache_dir, exist_ok=True)
                    
            # 创建文件名（包含版本和时间）
            version_tag = scheme_update_info.get('tag', 'unknown').replace('/', '_')
            date_str = remote_time.strftime("%Y%m%d")
            filename = os.path.join(update_cache_dir, f"update_{version_tag}_{date_str}.md")   

            # 移除已有的md文件
            for update_cache_file in os.listdir(update_cache_dir):
                if re.match('^update.*md$', update_cache_file) and update_cache_file != f"update_{version_tag}_{date_str}.md":
                    os.remove(os.path.join(update_cache_dir, update_cache_file))

            if not os.path.exists(filename):
                # 写入 Markdown 文件
                with open(filename, 'w', encoding='utf-8') as md_file:
                    md_file.write(f"# 方案更新说明 ({version_tag})\n\n")
                    md_file.write(f"**发布时间**: {scheme_local}\n\n")
                    md_file.write("## 更新内容\n\n")
                    md_file.write(raw_description)
            
                print_success(f"更新说明已保存到: {filename}")
        except Exception as e:
            print_error(f"保存更新说明失败: {str(e)}")
            
    # 词库更新提示(仅当有更新时显示)
    if has_dict_update:
        dict_update_info = dict_updater.update_info
        remote_time = datetime.strptime(dict_update_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        dict_local = remote_time.astimezone(timezone(timedelta(hours=8))).strftime("%Y-%m-%d %H:%M:%S")
        print(f"\n{COLOR['WARNING']}==== 词库更新可用 ===={COLOR['ENDC']}")
        print(f"版本: {dict_update_info.get('tag', '未知版本')}")
        print(f"发布时间: {dict_local}")
        
    # 模型更新提示(仅当有更新时显示)
    if has_model_update:
        model_update_info = model_updater.update_info
        remote_time = datetime.strptime(model_update_info["update_time"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        model_local = remote_time.astimezone(timezone(timedelta(hours=8))).strftime("%Y-%m-%d %H:%M:%S")
        print(f"\n{COLOR['WARNING']}==== 模型更新可用 ===={COLOR['ENDC']}")
        print(f"发布时间: {model_local}")
        
    # 如果没有更新显示提示
    if not (has_scheme_update or has_dict_update or has_model_update):
        print(f"\n{COLOR['OKGREEN']}[√] 所有组件均为最新版本{COLOR['ENDC']}")

def perform_auto_update(
    config_manager: ConfigManager, 
    combined_updater: Optional[CombinedUpdater] = None,
    is_config_triggered: bool = False
) -> Optional[List[int]]:
    """执行自动更新流程"""
    if not is_config_triggered:
        print_header("智能更新检测中...")
    
    # 创建或使用已有的组合更新器
    if combined_updater is None:
        # 只有在配置触发模式下才显示更新检查信息
        if is_config_triggered:
            print_subheader("正在检查可用更新...")
            use_mirror = config_manager.config.getboolean('Settings', 'use_mirror', fallback=False)
            if use_mirror:
                request_target = "cnb.cool" 
                print(f"{COLOR['WARNING']}脚本更新依然使用api.github.com，请保持网络畅通...{COLOR['ENDC']}")
            else:
                request_target = "api.github.com"
            print(f"{COLOR['BLUE']}请求 {request_target} 中...{COLOR['ENDC']}")
        
        combined_updater = CombinedUpdater(config_manager)
        combined_updater.fetch_all_updates()
    # 获取各个更新器的实例
    script_updater = combined_updater.script_updater
    scheme_updater = combined_updater.scheme_updater
    dict_updater = combined_updater.dict_updater
    model_updater = combined_updater.model_updater
    # 在配置触发模式下显示更新状态
    if is_config_triggered:
        print_update_status(scheme_updater, dict_updater, model_updater, script_updater)

    # 脚本更新检查（仅当有实际更新时才提示）
    if script_updater.update_info:
        script_updater.run()
        
    # 初始化更新状态
    scheme_updated = 0
    dict_updated = 0
    model_updated = 0
    if scheme_updater.has_update():
        scheme_updated = scheme_updater.run()
    if dict_updater.has_update():
        dict_updated = dict_updater.run()
    if model_updater.has_update():
        model_updated = model_updater.run()
    updated = [scheme_updated, dict_updated, model_updated]
    # 部署逻辑
    deployer = scheme_updater
    if SYSTEM_TYPE == 'windows':
        if -1 in updated and deployer:
            print("\n" + COLOR['OKCYAN'] + "[i]" + COLOR['ENDC'] + " 部分内容更新失败，跳过部署步骤，请重新更新")
            return updated # 直接返回updated，不进行后续操作
        elif updated == [0,0,0]  and deployer:
            print("\n" + COLOR['OKGREEN'] + "[√] 无需更新，跳过部署步骤" + COLOR['ENDC'])
        else:
            print_header("重新部署输入法")
            if deployer.deploy_weasel():
                print_success("部署成功")
            else:
                print_warning("部署失败，请检查日志")
    elif SYSTEM_TYPE == 'macos':
        if -1 in updated and deployer:
            print("\n" + COLOR['OKCYAN'] + "[i]" + COLOR['ENDC'] + " 部分内容更新失败，跳过部署步骤，请重新更新")
            return updated # 直接返回updated，不进行后续操作
        elif updated == [0,0,0]  and deployer:
            print("\n" + COLOR['OKGREEN'] + "[√] 无需更新，跳过部署步骤" + COLOR['ENDC'])
        else:
            print_header("重新部署输入法")
            deployer.deploy_for_mac()
    elif SYSTEM_TYPE == 'ios':
        import webbrowser
        if -1 in updated and deployer:
            print("\n" + COLOR['OKCYAN'] + "[i]" + COLOR['ENDC'] + " 部分内容更新失败，跳过部署步骤，请重新更新")
            return updated # 直接返回updated，不进行后续操作
        elif updated == [0,0,0]  and deployer:
            print("\n" + COLOR['OKGREEN'] + "[√] 无需更新，跳过部署步骤" + COLOR['ENDC'])
        else:
            print_header("尝试跳转到Hamster重新部署输入法")
            if is_config_triggered:
                # 配置触发的自动更新模式直接部署
                webbrowser.open("hamster://dev.fuxiao.app.hamster/rime?deploy", new=1)
                print_success("已自动触发部署")
            else:
                is_deploy = input("是否跳转到Hamster进行部署(y/n)? ").strip().lower()
                if is_deploy == 'y':
                    print_warning("将于3秒后跳转到Hamster输入法进行自动部署")
                    time.sleep(3)
                    webbrowser.open("hamster://dev.fuxiao.app.hamster/rime?deploy", new=1)
    else:
        if -1 in updated and deployer:
            print("\n" + COLOR['OKCYAN'] + "[i]" + COLOR['ENDC'] + " 部分内容更新失败，跳过部署步骤，请重新更新")
            return updated # 直接返回updated，不进行后续操作
        elif updated == [0,0,0]  and deployer:
            print("\n" + COLOR['OKGREEN'] + "[√] 无需更新，跳过部署步骤" + COLOR['ENDC'])
        else:
            print_warning("请手动部署输入法")

    print("\n" + COLOR['OKGREEN'] + "[√] 输入法配置全部更新完成" + COLOR['ENDC'])

    # 如果是配置触发的自动更新，直接退出
    if is_config_triggered:
        print("\n" + COLOR['OKGREEN'] +  "✨ 自动更新完成！" + COLOR['ENDC'])
        time.sleep(2)
        sys.exit(0)
    return updated

def create_and_show_updates(config_manager, show=True) -> CombinedUpdater:
    """创建并显示更新信息"""
    if show:
        print_subheader("正在检查可用更新...")
        use_mirror = config_manager.config.getboolean('Settings', 'use_mirror', fallback=False)
        if use_mirror:
            print(f"{COLOR['WARNING']}脚本更新依然使用api.github.com，请保持网络畅通...{COLOR['ENDC']}")
            request_target = "cnb.cool" 
        else:
            request_target = "api.github.com"
        print(f"{COLOR['BLUE']}请求 {request_target} 中...{COLOR['ENDC']}")
    
    # 创建组合更新器并获取所有更新信息
    combined_updater = CombinedUpdater(config_manager)
    combined_updater.fetch_all_updates()
    
    # 获取各个更新器的实例
    script_updater = combined_updater.script_updater
    scheme_updater = combined_updater.scheme_updater
    dict_updater = combined_updater.dict_updater
    model_updater = combined_updater.model_updater
    
    # 使用函数打印更新状态
    if show:
        print_update_status(scheme_updater, dict_updater, model_updater, script_updater)
    return combined_updater

def open_config_file(config_path) -> None:
    """用默认编辑器打开配置文件"""
    if os.name == 'nt':  # Windows
        subprocess.run(['notepad.exe', config_path], shell=True)
    else:  # macOS/Linux
        try:
            # 尝试使用默认编辑器打开
            if SYSTEM_TYPE == 'macos':
                subprocess.run(['open', config_path])
            else:
                subprocess.run(['xdg-open', config_path])
        except:
            print_warning("无法打开配置文件，请手动编辑。")

# ====================== 主程序 ======================
def main():
    print(f"\n{COLOR['OKCYAN']}[i] 当前系统为：{SYSTEM_TYPE} {COLOR['ENDC']}")
    if UPDATE_TOOLS_VERSION.startswith("DEFAULT"):
        print(f"{COLOR['WARNING']}[!] 您下载的是非发行版脚本，请勿直接使用，请去 releases 页面下载最新版本：https://github.com/rimeinn/rime-wanxiang-update-tools/releases{COLOR['ENDC']}")
    else:
        print(f"{COLOR['OKCYAN']}[i] 当前更新工具版本：{UPDATE_TOOLS_VERSION}{COLOR['ENDC']}")    

    try:
        config_manager = ConfigManager()
        combined_updater = None  # 初始化组合更新器
        
        # 检查是否启用了自动更新
        auto_update = config_manager.config.getboolean('Settings', 'auto_update', fallback=False)
        if auto_update:
            print_header("自动更新模式已启用")
            combined_updater = create_and_show_updates(config_manager, show=False)
            # 执行自动更新并退出
            perform_auto_update(
                config_manager, 
                combined_updater=combined_updater, 
                is_config_triggered=True
            )
        # 非自动更新模式下显示更新状态
        if not auto_update:
            # 创建并显示更新信息
            combined_updater = create_and_show_updates(config_manager)
        # 主菜单循环
        while True:
            # 选择更新类型
            print_header("更新类型选择") 
            print("[1] 词库下载\n[2] 方案下载\n[3] 模型下载\n[4] 自动更新\n[5] 脚本更新\n[6] 修改配置\n[7] 退出程序")
            choice = input("请输入选择（1-7，单独按回车键默认选择自动更新）: ").strip() or '4'
            
            if choice == '6':
                # 修改配置
                config_manager.display_config_instructions()
                print("保存后关闭配置文件以继续...")
                open_config_file(config_manager.config_path)
                # 返回主菜单或退出
                user_choice = input("\n按回车键返回主菜单，或输入其他键退出: ").strip().lower()
                if user_choice == '':
                    # 重新加载配置
                    config_manager = ConfigManager()
                    # 重置更新器
                    combined_updater = None
                    # 重新创建并显示更新信息
                    combined_updater = create_and_show_updates(config_manager)
                else:
                    break
            elif choice == '7':
                break
            elif choice == '5':
                # 脚本更新
                script_updater = combined_updater.script_updater
                script_updater.run()
                continue
            elif choice == '4':  # 自动更新选项
                # 确保有更新器实例
                if not combined_updater:
                    combined_updater = create_and_show_updates(config_manager)
                # 执行自动更新
                updated = perform_auto_update(
                    config_manager, 
                    combined_updater=combined_updater, 
                    is_config_triggered=False
                )
                # 处理更新结果
                if -1 in updated:
                    print_warning("部分内容下载更新失败，请重试")
                    continue
                else:
                    print_success(COLOR['OKGREEN'] + "自动更新完成" + COLOR['ENDC'])
                    sys.exit(0)
            else:
                # 执行其他更新操作,确保有更新器实例
                if not combined_updater:
                    combined_updater = create_and_show_updates(config_manager)
                # 获取各个更新器的实例
                scheme_updater = combined_updater.scheme_updater
                dict_updater = combined_updater.dict_updater
                model_updater = combined_updater.model_updater
                # 初始化更新状态
                deployer = None
                updated = -200
                if choice == '1':
                    updated = dict_updater.run()
                    deployer = dict_updater
                elif choice == '2':
                    updated = scheme_updater.run()
                    deployer = scheme_updater
                elif choice == '3':
                    updated = model_updater.run()
                    deployer = model_updater
                # 部署逻辑
                if SYSTEM_TYPE == 'windows' and deployer and updated == 1:
                    print_header("重新部署输入法")
                    if deployer.deploy_weasel():
                        print_success("部署成功")
                    else:
                        print_warning("部署失败，请检查日志")
                elif SYSTEM_TYPE == 'macos' and deployer and updated == 1:
                    print_header("重新部署输入法")
                    deployer.deploy_for_mac()
                elif SYSTEM_TYPE == 'ios' and deployer and updated == 1:
                    import webbrowser
                    print_header("尝试跳转到Hamster重新部署输入法")
                    is_deploy = input("是否跳转到Hamster进行部署(y/n)? ").strip().lower()
                    if is_deploy == 'y':
                        print_warning("将于3秒后跳转到Hamster输入法进行自动部署")
                        time.sleep(3)
                        webbrowser.open("hamster://dev.fuxiao.app.hamster/rime?deploy", new=1)
                else:
                    if deployer and updated == 1:
                        print_warning("请手动部署输入法")

                # 返回主菜单或退出
                user_input = input("\n按回车键返回主菜单，或输入其他键退出: ")
                if user_input.strip().lower() == '':
                    continue  # 继续主循环
                else:
                    break

        print("\n✨ 升级完毕，欢迎下次使用！")
        time.sleep(2)
        sys.exit(0)
    except KeyboardInterrupt:
        print(f"\n{COLOR['FAIL']}🚫 终止操作 {COLOR['ENDC']}")
    except SystemExit:
        print(f"\n{COLOR['OKBLUE']}⏏️ 程序退出 {COLOR['ENDC']}")
    except Exception as e:
        print(f"\n{COLOR['FAIL']}💥 程序异常：{str(e)}{COLOR['ENDC']}")
        sys.exit(1)

if __name__ == "__main__":
    main()
