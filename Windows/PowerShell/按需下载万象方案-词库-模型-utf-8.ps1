#本项目地址： https://github.com/rimeinn/rime-wanxiang-update-tools
# ======= 命令行参数定义，必须放在脚本最顶部 =======
param(
    [string]$schemaType,
    [string]$cliTargetFolder,
    [switch]$noSchema,
    [switch]$noDict,
    [switch]$noModel,
    [switch]$disableCNB,
    [switch]$disableAutoReDeploy,
    [switch]$auto,
    [switch]$useCurl,
    [string]$skipFiles,
    [switch]$help,
    [switch]$debug
)

function Exit-Tip {
    param(
        [string]$exitCode = 0
    )
    Write-Host '按任意键退出...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit $exitCode
}

if ($auto -and (-not $schemaType -or $schemaType -notmatch '^[0-6]$')) {
    Write-Host "错误：自动模式下必须通过 -schemaType 指定方案类型编号（0-6），如 -schemaType 6" -ForegroundColor Red
    Exit-Tip 1
}

if ($help -or $args -contains '-h' -or $args -contains '--help') {
    # 仅在非 help 模式下强制要求 schemaType
    if (-not $help -and -not ($args -contains '-h') -and -not ($args -contains '--help')) {
        if (-not $schemaType) {
            Write-Host "错误：-schemaType 参数为必填项，请指定方案类型编号（0-6）。" -ForegroundColor Red
            Write-Host "示例：pwsh -File .\\按需下载万象方案-词库-模型-utf-8.ps1 -schemaType 6"
            Exit-Tip 1
        }
    }
    Write-Host "Rime 万象 PowerShell 更新工具 - 命令行参数说明" -ForegroundColor Cyan
    Write-Host "---------------------------------------------"
    Write-Host "-schemaType <编号>    方案类型编号，0-6 (如 6 表示自然码)"
    Write-Host "-noSchema            不更新方案"
    Write-Host "-noDict              不更新词库"
    Write-Host "-noModel             不更新模型"
    Write-Host "-cliTargetFolder <路径>  指定目标安装目录，优先于注册表读取（如果提供，将对路径存在性和写权限进行检查）"
    Write-Host "-auto                启用自动更新模式"
    Write-Host "-debug               启用调试模式(输出更多调试信息)"
    Write-Host "-useCurl             使用curl.exe提升下载速度并减少中断"
    Write-Host "-disableCNB          不使用 CNB 镜像源"
    Write-Host "-disableAutoReDeploy 不自动触发重新部署"
    Write-Host "-skipFiles <文件1,文件2,...>  跳过指定文件，逗号分隔"
    Write-Host "-h, --help           显示本帮助信息"
    Write-Host "示例："
    Write-Host "pwsh -ExecutionPolicy Bypass -File .\\按需下载万象方案-词库-模型-utf-8.ps1 -schemaType 6 -auto -noModel"
    Write-Host "pwsh -File .\\按需下载万象方案-词库-模型-utf-8.ps1 -schemaType 1 -skipFiles 'wanxiang_en.dict.yaml,tone_fallback.lua'"
    Exit-Tip 0
}

############# 自动更新配置项，配置好后将 AutoUpdate 设置为 true 即可 #############
$AutoUpdate = $false;

# 是否使用 CNB 镜像源，如果设置为 $true，则从 CNB 获取资源；否则从 GitHub 获取。
$UseCnbMirrorSource = $true

# 是否使用 curl.exe 代替 Invoke-WebRequest，提升下载速度，并减少下载中断
$UseCurl = $false

# 设置自动更新时，是否更新方案、词库、模型，不想更新某项就改成false
$IsUpdateSchemaDown = $true
$IsUpdateDictDown = $true
$IsUpdateModel = $true

# 设置自动更新时选择的方案，注意必须包含双引号，例如：$InputSchemaType = "0";
# [0]-标准版; [1]-小鹤; [2]-汉心; [3]-墨奇; [4]-虎码; [5]-五笔; [6]-自然码"
$InputSchemaType = "6";

# 设置自动更新时要跳过的文件列表，配置好后删除注释符号
# $SkipFiles = @(
#     "wanxiang_symbols.yaml",
#     "weasel.yaml",
#     "others.txt"
# );

# 设置代理地址和端口，配置好后删除注释符号
# $proxyAddress = "http://127.0.0.1:7897"
# [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxyAddress)
# [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

# 设置GitHub Token请求头，防止api请求失败403错误，配置好后删除注释符号
# $env:GITHUB_TOKEN = "填入这里你的token字符串"    #打开链接https://github.com/settings/tokens，注册一个token# (Public repositories) 

############# 自动更新配置项，配置好后将 AutoUpdate 设置为 true 即可 #############

$Debug = $false;

# 支持命令行参数覆盖关键选项
# 通过命令行参数覆盖配置
if ($PSBoundParameters.ContainsKey('schemaType')) {
    $InputSchemaType = $schemaType
}
if ($PSBoundParameters.ContainsKey('auto')) {
    $AutoUpdate = $true
}
if ($PSBoundParameters.ContainsKey('disableCNB')) {
    $UseCnbMirrorSource = $false
}
if ($PSBoundParameters.ContainsKey('useCurl')) {
    $UseCurl = $true
}
if ($PSBoundParameters.ContainsKey('noSchema')) {
    $IsUpdateSchemaDown = $false
}
if ($PSBoundParameters.ContainsKey('noDict')) {
    $IsUpdateDictDown = $false
}
if ($PSBoundParameters.ContainsKey('noModel')) {
    $IsUpdateModel = $false
}
if ($PSBoundParameters.ContainsKey('debug')) {
    Write-Host "启用 debug 模式"
    $Debug = $true
}
if ($PSBoundParameters.ContainsKey('skipFiles')) {
    Write-Host "重新赋值 SkipFiles"
    # 支持以逗号或任意空白分隔的多项输入，例如:
    # -skipFiles 'a.txt,b.txt' 或 -skipFiles 'a.txt b.txt' 或 -skipFiles 'a.txt, b.txt'
    if ($skipFiles -is [string]) {
        $items = $skipFiles -split '[,\s]+'
    } else {
        $items = $skipFiles
    }
    # 去除空项、两端空白并去重
    $SkipFiles = $items | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Select-Object -Unique
    Write-Host "最终 SkipFiles 内容：" $SkipFiles
}
# 如果命令行提供了 cliTargetFolder 参数，则优先使用并验证
if ($PSBoundParameters.ContainsKey('cliTargetFolder') -and $cliTargetFolder) {
    try {
        $resolvedPath = Resolve-Path -Path $cliTargetFolder -ErrorAction Stop
        $resolvedPath = $resolvedPath.ProviderPath
    }
    catch {
        Write-Host "错误：指定的目标文件夹不存在： $cliTargetFolder" -ForegroundColor Red
        Exit-Tip 1
    }

    if (-not (Test-Path $resolvedPath -PathType Container)) {
        Write-Host "错误：指定路径不是目录： $resolvedPath" -ForegroundColor Red
        Exit-Tip 1
    }

    # 检查写权限：尝试创建并删除临时文件
    try {
        $permTestFile = Join-Path $resolvedPath ".wanxiang_perm_test_$([System.Guid]::NewGuid().ToString()).tmp"
        New-Item -Path $permTestFile -ItemType File -Force -ErrorAction Stop | Out-Null
        Remove-Item -Path $permTestFile -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "错误：没有对目标目录的写入权限： $resolvedPath" -ForegroundColor Red
        Exit-Tip 1
    }
}

$UpdateToolsVersion = "DEFAULT_UPDATE_TOOLS_VERSION_TAG";
if ($UpdateToolsVersion.StartsWith("DEFAULT")) {
    Write-Host "您下载的是非发行版脚本，请勿直接使用，请去 releases 页面下载最新版本：https://github.com/rimeinn/rime-wanxiang-update-tools/releases" -ForegroundColor Yellow;
} else {
    Write-Host "当前更新工具版本：$UpdateToolsVersion" -ForegroundColor Yellow;
}

# 设置仓库所有者和名称
$UpdateToolsOwner = "rimeinn"
$UpdateToolsRepo = "rime-wanxiang-update-tools"
# 定义临时文件路径基准（具体临时文件路径在确定 $targetDir 后设置）
$BaseTempPath = [System.IO.Path]::GetTempPath()

$GramModelFileName = "wanxiang-lts-zh-hans.gram"
$ReleaseTimeRecordFile = "release_time_record.json"

if ($UseCnbMirrorSource) {
    $SchemaOwner = "amzxyz"
    $SchemaRepo = "rime-wanxiang"
    $GramRepo = "RIME-LMDG"
    $GramReleaseTag = "model"
    $DictReleaseTag = "v1.0.0"
} else {
    $SchemaOwner = "amzxyz"
    $SchemaRepo = "rime_wanxiang"
    $GramRepo = "RIME-LMDG"
    $GramReleaseTag = "LTS"
    $DictReleaseTag = "dict-nightly"
}

$KeyTable = @{
    "0" = "base";
    "1" = "flypy";
    "2" = "hanxin";
    "3" = "moqi";
    "4" = "tiger";
    "5" = "wubi";
    "6" = "zrm";
}

$UriHeader = @{
    "accept"="application/vnd.cnb.web+json"
    "cache-control"="no-cache"
    'Accept-Charset' = 'utf-8'
}

$SchemaDownloadTip = "[0]-标准版; [1]-小鹤; [2]-汉心; [3]-墨奇; [4]-虎码; [5]-五笔; [6]-自然码";

$GramKeyTable = @{
    "0" = "zh-hans.gram";
}

$GramFileTableIndex = 0;

$DictFileSaveDirTable = @{
    "base" = "dicts";
    "pro" = "dicts";
}

$DictFileSaveDirTableIndex = "base";

# 设置安全协议为TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 获取 Weasel 用户目录路径
function Get-RegistryValue {
    param(
        [string]$regPath,
        [string]$regValue
    )
    
    try {
        # 获取注册表值
        $value = (Get-ItemProperty -Path $regPath -Name $regValue).$regValue
        # 返回结果
        return $value
    }
    catch {
        Write-Host "警告：注册表路径 $regPath 不存在，请检查输入法是否正确安装" -ForegroundColor Yellow
        return $null
    }
}

function Get-FileNameWithoutExtension {
    param(
        [string]$filePath
    )
    $fileName = Split-Path $filePath -Leaf
    return $fileName -replace '\.[^.]+$', ''
}

function Get-DictExtractedFolderPath {
    param(
        [string]$extractPath,
        [string]$assetName
    )
    $folders = Get-ChildItem -Path $extractPath -Directory
    if ($folders.Count -eq 0) {
        Write-Host "错误：解压后的目录中没有找到任何文件夹" -ForegroundColor Red
        Exit-Tip 1
    } elseif ($folders.Count -gt 1) {
        Write-Host "警告：解压后的目录中有多个文件夹，将使用第一个文件夹" -ForegroundColor Yellow
        Write-Host "文件夹名称: $($folders[0].Name)" -ForegroundColor Green
        return $folders[0].FullName
    } else {
        Write-Host "解压后的目录中只有一个文件夹，将使用该文件夹" -ForegroundColor Green
        Write-Host "文件夹名称: $($folders[0].Name)" -ForegroundColor Green
        return $folders[0].FullName
    }
}

function Get-WeaselUserDir {
    try {
        $userDir = Get-RegistryValue -regPath "HKCU:\Software\Rime\Weasel" -regValue "RimeUserDir"
        if (-not $userDir) {
            # appdata 目录下的 Rime 目录
            $userDir = Join-Path $env:APPDATA "Rime"
        }
        return $userDir
    }
    catch {
        Write-Host "警告：未找到Weasel用户目录，请确保已正确安装小狼毫输入法" -ForegroundColor Yellow
    }
}

function Get-WeaselInstallDir {
    try {
        return Get-RegistryValue -regPath "HKLM:\SOFTWARE\WOW6432Node\Rime\Weasel" -regValue "WeaselRoot"
    }
    catch {
        Write-Host "警告：未找到Weasel安装目录，请确保已正确安装小狼毫输入法" -ForegroundColor Yellow
        return $null
    }
}

function Get-WeaselServerExecutable {
    try {
        return Get-RegistryValue -regPath "HKLM:\SOFTWARE\WOW6432Node\Rime\Weasel" -regValue "ServerExecutable"
    }
    catch {
        Write-Host "警告：未找到Weasel服务端可执行程序，请确保已正确安装小狼毫输入法" -ForegroundColor Yellow
        return $null
    }
}

function Test-SkipFile {
    param(
        [string]$filePath
    )
    # 规范化输入
    if (-not $filePath) { return $false }
    $fullPath = [System.IO.Path]::GetFullPath($filePath) 2>$null
    if (-not $fullPath) { $fullPath = $filePath }
    $baseName = Get-FileNameWithoutExtension($filePath)
    $fileName = Split-Path $filePath -Leaf

    if ($Debug) {
        Write-Host "Testing skip for file: $filePath" -ForegroundColor Cyan
        Write-Host "Full path: $fullPath" -ForegroundColor Cyan
        Write-Host "Base name: $baseName" -ForegroundColor Cyan
        Write-Host "File name: $fileName" -ForegroundColor Cyan
    }

    # 确保 $SkipFiles 是数组
    $skipList = @()
    if ($null -ne $SkipFiles) {
        if ($SkipFiles -is [string]) {
            $skipList = @($SkipFiles)
        } else {
            $skipList = $SkipFiles
        }
    }

    if ($Debug) {
        Write-Host "Debug: checking skip list items (count=$($skipList.Count))" -ForegroundColor Cyan
        $i = 0
        foreach ($item in $skipList) {
            if ($null -eq $item) { Write-Host "  [$i] <null>" -ForegroundColor Cyan }
            else { Write-Host "  [$i] '$item' (len=$($item.Length))" -ForegroundColor Cyan }
            $i++
        }
        Write-Host "Debug: fileName='$fileName' (len=$($fileName.Length)), baseName='$baseName' (len=$($baseName.Length)), fullPath='$fullPath'" -ForegroundColor Cyan
    }

    # 兜底：如果 skipList 仅有一项且该项内部含空格或逗号，可能来自旧格式的单字符串，拆分后使用
    if ($skipList.Count -eq 1 -and $skipList[0] -match '[,\s]') {
        if ($Debug) { Write-Host "Debug: single skipList item contains separators, splitting into multiple items" -ForegroundColor Cyan }
        $splitItems = $skipList[0] -split '[,\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Select-Object -Unique
        $skipList = $splitItems
        if ($Debug) { Write-Host "Debug: new skip list count=$($skipList.Count)" -ForegroundColor Cyan }
    }

    foreach ($s in $skipList) {
        if (-not $s) { continue }
        $pattern = $s
        $patternTrim = $pattern
        if ($patternTrim) { $patternTrim = $patternTrim.Trim() }
        # if ($Debug) { Write-Host "Checking pattern: '$pattern' (trimmed: '$patternTrim')" -ForegroundColor Cyan }
        # 如果包含通配符，使用 -like 来匹配完整路径或文件名
        if ($pattern -match '[\*\?]') {
            if ($fullPath -like $patternTrim -or $fileName -like $patternTrim) {
                if ($Debug) { Write-Host "Skip match (wildcard) '$pattern' -> '$filePath'" -ForegroundColor Yellow }
                return $true
            }
        }
        else {
            # 精确匹配完整路径
            try {
                $resolvedSkip = [System.IO.Path]::GetFullPath($patternTrim) 2>$null
            } catch { $resolvedSkip = $null }
            if ($resolvedSkip -and ($resolvedSkip -eq $fullPath)) {
                if ($Debug) { Write-Host "Skip match (fullpath) '$pattern' -> '$filePath'" -ForegroundColor Yellow }
                return $true
            }

            # 精确匹配文件名
            if ($patternTrim -ieq $fileName -or $patternTrim -ieq $baseName) {
                if ($Debug) { Write-Host "Skip match (name) '$pattern' -> '$filePath'" -ForegroundColor Yellow }
                return $true
            }

            # 支持以路径结尾匹配（例如 'subdir/file.txt' 与 完整路径结尾匹配）
            if ($patternTrim -and $fullPath.EndsWith($patternTrim, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($Debug) { Write-Host "Skip match (endswith) '$pattern' -> '$filePath'" -ForegroundColor Yellow }
                return $true
            }
        }
    }

    if ($Debug) { Write-Host "No skip match for '$filePath'" -ForegroundColor Green }
    return $false
}

# 调用函数并赋值给变量
$rimeUserDir = Get-WeaselUserDir
$rimeInstallDir = Get-WeaselInstallDir
$rimeServerExecutable = Get-WeaselServerExecutable

function Stop-WeaselServer {
    if (-not $rimeServerExecutable) {
        Write-Host "警告：未找到Weasel服务端可执行程序，请确保已正确安装小狼毫输入法" -ForegroundColor Yellow
        Exit-Tip 1
    } elseif (-not $SkipStopWeasel) {
        # 优先尝试按进程名强制结束（来自 get-rime.ps1 的 KillWeaselServer 逻辑）
        $processName = 'WeaselServer'
        try {
            $proc = Get-Process -Name $processName -ErrorAction SilentlyContinue
        } catch {
            $proc = $null
        }
        if ($proc) {
            while ($proc) {
                try {
                    Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
                } catch {
                    # 忽略停止错误，继续尝试
                }
                Start-Sleep -Seconds 0.5
                try {
                    $proc = Get-Process -Name $processName -ErrorAction SilentlyContinue
                } catch {
                    $proc = $null
                }
            }
            Write-Host "☑  $processName has been killed" -ForegroundColor Green
        } else {
            # 如果没有找到运行中的进程，尝试通过可执行文件的 /q 参数触发优雅停止（保留原行为作为兜底）
            try {
                Start-Process -FilePath (Join-Path $rimeInstallDir $rimeServerExecutable) -ArgumentList '/q' -ErrorAction SilentlyContinue | Out-Null
                Write-Host "尝试使用可执行文件的 /q 参数触发停止（若支持）" -ForegroundColor Yellow
            } catch {
                Write-Host "无法触发可执行文件停止：$($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

function Start-WeaselServer {
    if (-not $rimeServerExecutable) {
        Write-Host "警告：未找到Weasel服务端可执行程序，请确保已正确安装小狼毫输入法" -ForegroundColor Yellow
        Exit-Tip 1
    } elseif (-not $SkipStopWeasel) {
        Start-Process -FilePath (Join-Path $rimeInstallDir $rimeServerExecutable)
    }
}

function Start-WeaselReDeploy{
    $defaultShortcutPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\小狼毫输入法\【小狼毫】重新部署.lnk"
    $backupEnglishShortcutPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Weasel\Weasel Deploy.lnk"
    if ($disableAutoReDeploy) {
        Write-Host "跳过触发重新部署" -ForegroundColor Yellow
    } elseif (-not $SkipStopWeasel) {
        if (Test-Path -Path $defaultShortcutPath) {
            Write-Host "找到默认【小狼毫】重新部署快捷方式，将执行" -ForegroundColor Green
            Invoke-Item -Path $defaultShortcutPath
        } elseif (Test-Path -Path $backupEnglishShortcutPath) {
            Write-Host "找到默认【小狼毫】重新部署快捷方式，将执行" -ForegroundColor Green
            Invoke-Item -Path $backupEnglishShortcutPath
        } else {
            Write-Host "未找到默认的【小狼毫】重新部署快捷方式，将尝试执行默认的重新部署命令" -ForegroundColor Yellow
            Write-Host "跳过触发重新部署" -ForegroundColor Yellow
        }
    }
}

# 检查必要路径是否为空
if (-not $rimeUserDir -or -not $rimeInstallDir -or -not $rimeServerExecutable) {
    Write-Host "错误：无法获取Weasel必要路径，请检查输入法是否正确安装" -ForegroundColor Red
    Exit-Tip 1
}

# 如果命令行提供了 cliTargetFolder 参数，则优先使用并验证
if ($PSBoundParameters.ContainsKey('cliTargetFolder') -and $cliTargetFolder) {
    Write-Host "通过 cli 配置的目标文件夹为: $resolvedPath" -ForegroundColor Green
    $targetDir = $resolvedPath
} else {
    Write-Host "Weasel用户目录路径为: $rimeUserDir" -ForegroundColor Green
    $targetDir = $rimeUserDir
}

# 在目标用户目录下创建专用临时目录用于保存下载的zip等（保留zip，供后续检查）
$WanxiangTempDir = Join-Path $targetDir 'wanxiang_temp'
if (-not (Test-Path $WanxiangTempDir)) {
    try {
        New-Item -Path $WanxiangTempDir -ItemType Directory -Force | Out-Null
        Write-Host "已创建临时目录: $WanxiangTempDir" -ForegroundColor Green
    } catch {
        Write-Host "警告：无法创建临时目录 $WanxiangTempDir，将使用系统临时目录" -ForegroundColor Yellow
        $WanxiangTempDir = $BaseTempPath
    }
}
# 将 schema 临时 zip 文件放置在用户目录下的专用临时目录中
$tempSchemaZip = Join-Path $WanxiangTempDir "wanxiang_schema_temp.zip"
# 将 dict 临时 zip 和 gram 临时文件也放在该目录
$tempDictZip = Join-Path $WanxiangTempDir "wanxiang_dict_temp.zip"
$tempGram = Join-Path $WanxiangTempDir "wanxiang-lts-zh-hans.gram"

# 将解压目录也放在用户临时目录下的子目录，保持与 zip 存放在同一工作目录
$SchemaExtractPath = Join-Path $WanxiangTempDir "wanxiang_schema_extract"
$DictExtractPath = Join-Path $WanxiangTempDir "wanxiang_dict_extract"

# 确保解压目录存在；如果无法创建则回退到系统临时目录
foreach ($d in @($SchemaExtractPath, $DictExtractPath)) {
    if (-not (Test-Path $d)) {
        try {
            New-Item -Path $d -ItemType Directory -Force | Out-Null
        }
        catch {
            Write-Host "警告：无法创建解压目录 $d，将回退到系统临时目录" -ForegroundColor Yellow
            $SchemaExtractPath = Join-Path $BaseTempPath "wanxiang_schema_extract"
            $DictExtractPath = Join-Path $BaseTempPath "wanxiang_dict_extract"
            break
        }
    }
}

if ($targetDir -eq $rimeUserDir) {
    $SkipStopWeasel = $false
} else {
    $SkipStopWeasel = $true
}

$TimeRecordFile = Join-Path $targetDir $ReleaseTimeRecordFile

function Test-VersionSuffix {
    param(
        [string]$url
    )
    # tag_name = v1.0.0 or v1.0
    $pattern = 'v(\d+)(\.\d+)+'
    if ($UseCnbMirrorSource) {
        return $url -match $pattern | Where-Object { $_ -notmatch $DictReleaseTag -and $_ -notmatch $GramReleaseTag }
    }
    else {
        return $url -match $pattern
    }
}

function Test-DictSuffix {
    param(
        [string]$url
    )

    return $url -match $DictReleaseTag
}

function Test-CnbGramSuffix {
    param(
        [string]$url
    )
    # tag_name = model
    return $url -match $GramReleaseTag
}

function Invoke-FileUtf8 {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [hashtable]$Headers
    )
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri $Uri -Headers $Headers -OutFile $tmp
        $bytes = [System.IO.File]::ReadAllBytes($tmp)
        $text  = [System.Text.Encoding]::UTF8.GetString($bytes)
        return $text
    } catch {
        Write-Error "错误：下载或解析文件失败: $Uri"
        Write-Error $_.Exception.Message
        Exit-Tip 1
    } finally {
            Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

function Get-CnbReleaseInfo {
    param(
        [string]$owner,
        [string]$repo,
        [string]$query
    )

    # https://cnb.cool/amzxyz/rime-wanxiang/-/releases?page=1&page_size=20&query=
    $apiUrl = "https://cnb.cool/$owner/$repo/-/releases?page=1&page_size=100&query=$query"

    try {
        Write-Host "正在从 CNB 页面获取信息: $apiUrl" -ForegroundColor Cyan
        $jsonDataTmp = Invoke-FileUtf8 -Uri $apiUrl -Headers $UriHeader
        $jsonDataFormat = $jsonDataTmp | ConvertFrom-Json
      
        if ($jsonDataFormat.releases){
            $releaseData = $jsonDataFormat.releases
            Write-Host "成功获取 CNB release 版本信息" -ForegroundColor Green
            if ($jsonDataFormat.release_count -eq 0) {
                Write-Error "CNB release 版本没有可下载资源"
                Exit-Tip 1
            }
            return $releaseData
        } else {
            Write-Error "错误：在页面中未找到 'release' 数据。"
            Exit-Tip 1
        }
    }
    catch {
        Write-Error "错误：下载或解析CNB页面失败: $apiUrl"
        Write-Error $_.Exception.Message
        Exit-Tip 1
    }
}

function Get-GithubReleaseInfo {
    param(
        [string]$owner,
        [string]$repo
    )
    # 构建API请求URL
    $apiUrl = "https://api.github.com/repos/$owner/$repo/releases"

    # 构建API请求头
    $GitHubHeaders = @{
        "User-Agent" = "PowerShell Release Downloader"
        "Accept"     = "application/vnd.github.v3+json"
    }
    if ($env:GITHUB_TOKEN) {
        $GitHubHeaders["Authorization"] = "token $($env:GITHUB_TOKEN)"
    }
    
    try {
        # 发送API请求
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $GitHubHeaders
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        if ($statusCode -eq 404) {
            Write-Error "错误：仓库 '$owner/$repo' 不存在或没有发布版本"
        }
        else {
            Write-Error "API请求失败 [$statusCode]：$_"
        }
        return $null
    }

    # 检查是否有可下载资源
    if ($response.assets.Count -eq 0) {
        Write-Error "该版本没有可下载资源"
        return $null
    }
    return $response
}

function Get-ReleaseInfo {
    param(
        [string]$owner,
        [string]$repo,
        [bool]$updateToolFlag = $false,
        [string]$query
    )
    # 构建API请求URL
    if ($updateToolFlag) {
        Write-Host "正在尝试获取更新工具自身版本信息..." -ForegroundColor Cyan
        $result = Get-GithubReleaseInfo -owner $owner -repo $repo
        if ($null -eq $result) {
            Write-Host "获取更新工具版本信息失败，将跳过自身更新检查。" -ForegroundColor Cyan
            return @() # 如果自身更新信息获取失败，返回空数组，不终止脚本
        }
        return $result
    }
    if ($UseCnbMirrorSource){
        return Get-CnbReleaseInfo -owner $owner -repo $repo -query $query
    } else {
        $result = Get-GithubReleaseInfo -owner $owner -repo $repo
        if ($null -eq $result) {
            Write-Error "错误：无法获取仓库 '$owner/$repo' 的发布版本信息。" -ForegroundColor Cyan
            Exit-Tip 1 # 对于非自身更新的 GitHub 资源获取失败，仍旧退出脚本
        }
        return $result
    }
}

$UpdateTollsResponse = Get-ReleaseInfo -owner $UpdateToolsOwner -repo $UpdateToolsRepo -updateToolFlag $true
# 检测是否需要跳过自身更新检查
$SkipSelfUpdateCheck = $false
if ($null -eq $UpdateTollsResponse -or $UpdateTollsResponse.Count -eq 0) {
    $SkipSelfUpdateCheck = $true
    $UpdateTollsResponse = @() 
}

# 检查是否有新版本,如果获取的版本信息比现在的版本信息(UpdateToolsVersion)新，则提示用户更新
# 版本格式:v3.4.0,v3.4.1,v3.4.1-rc1,不比较 rc 版本
if (-not $SkipSelfUpdateCheck) {
    $StableUpdateToolsReleases = $UpdateTollsResponse 
    
    if ($StableUpdateToolsReleases.Count -eq 0) {
        Write-Host "没有找到稳定版的更新工具版本信息，跳过自身更新检查。" -ForegroundColor Yellow
    } else {
        $LatestUpdateToolsRelease = $StableUpdateToolsReleases | Select-Object -First 1
        if ($LatestUpdateToolsRelease.tag_name -ne $UpdateToolsVersion) {
            Write-Host "发现新版本的更新工具: $($LatestUpdateToolsRelease.tag_name)" -ForegroundColor Yellow
            Write-Host "如需更新,请访问 https://github.com/rimeinn/rime-wanxiang-update-tools/releases 下载最新版本" -ForegroundColor Yellow
            Write-Host "当前版本: $UpdateToolsVersion" -ForegroundColor Yellow
            Write-Host "更新日志: $($LatestUpdateToolsRelease.body)" -ForegroundColor Yellow
        } else {
            Write-Host "脚本工具已是最新版本：$UpdateToolsVersion" -ForegroundColor Green
        }
    }
}

# 获取最新的版本信息
$SchemaResponse = Get-ReleaseInfo -owner $SchemaOwner -repo $SchemaRepo
if ($UseCnbMirrorSource) {
    $GramResponse = Get-ReleaseInfo -owner $SchemaOwner -repo $SchemaRepo -query "model"
} else {
    $GramResponse = Get-ReleaseInfo -owner $SchemaOwner -repo $GramRepo
}

$SelectedDictRelease = $null
$SelectedSchemaRelease = $null
$SelectedGramRelease = $null

function Get-ReleaseTagName {
    param(
        [object]$release
    )
    if ($UseCnbMirrorSource) {
        $tag_name = $release.tag_ref
    } else {
        $tag_name = $release.tag_name
    }
    return $tag_name
}

foreach ($release in $SchemaResponse) {
    $tag_name = Get-ReleaseTagName -release $release

    if (($null -eq $SelectedDictRelease) -and (Test-DictSuffix -url $tag_name)) {
        $SelectedDictRelease = $release
        continue
    }
    if ((-not $SelectedSchemaRelease) -and (Test-VersionSuffix -url $tag_name)) {
        $SelectedSchemaRelease = $release
    }
    if ($SelectedDictRelease -and $SelectedSchemaRelease) {
        break
    }
}

foreach ($release in $GramResponse) {
    $tag_name = Get-ReleaseTagName -release $release
    if ($Debug) {
        Write-Host "release.tag_name: $tag_name" -ForegroundColor Green
        Write-Host "GramReleaseTag: $GramReleaseTag" -ForegroundColor Green
    }
    if ($tag_name -match $GramReleaseTag) {
        $SelectedGramRelease = $release
    }
}

if ($SelectedDictRelease -and $SelectedSchemaRelease -and $SelectedGramRelease) {
    if (-not $UseCnbMirrorSource) {
        Write-Host "解析出最新的词库链接为：$($SelectedDictRelease.html_url)" -ForegroundColor Green
        Write-Host "解析出最新的版本链接为：$($SelectedSchemaRelease.html_url)" -ForegroundColor Green
        Write-Host "解析出最新的模型链接为：$($SelectedGramRelease.html_url)" -ForegroundColor Green
    }
} else {
    Write-Error "未找到符合条件的版本或词库链接"
    Exit-Tip 1
}

# 获取最新的版本的tag_name
if (-not $UseCnbMirrorSource) {
    Write-Host "方案最新的版本为：$($SelectedSchemaRelease.tag_name)"
    Write-Host "方案更新日志: " -ForegroundColor Yellow
    Write-Host $SelectedSchemaRelease.body -ForegroundColor Yellow
} else {
    Write-Host "方案最新的版本为：$($SelectedSchemaRelease.tag_ref)"
    Write-Host "方案更新日志: " -ForegroundColor Yellow
    Write-Host $SelectedSchemaRelease.body -ForegroundColor Yellow
}


$promptSchemaType = "请选择你要下载的方案类型的编号: `n$SchemaDownloadTip"
$promptAllUpdate = "是否更新所有内容（方案、词库、模型）:`n[0]-更新所有; [1]-不更新所有"
$promptSchemaDown = "是否下载方案:`n[0]-下载; [1]-不下载"
$promptGramModel = "是否下载模型:`n[0]-下载; [1]-不下载"
$promptDictDown = "是否下载词库:`n[0]-下载; [1]-不下载"

if ($AutoUpdate) {
    Write-Host "自动更新模式，将自动下载最新的版本" -ForegroundColor Green
    Write-Host "你配置的方案号为：$InputSchemaType" -ForegroundColor Green
    # 方案号只支持0-6
    if ($InputSchemaType -lt 0 -or $InputSchemaType -gt 6) {
        Write-Error "错误：方案号只能是0-6"
        Exit-Tip 1
    }
    $InputAllUpdate = "0"
    $InputSchemaDown = if ($IsUpdateSchemaDown)  { "0" } else { "1" }
    $InputGramModel = if ($IsUpdateModel)  { "0" } else { "1" }
    $InputDictDown = if ($IsUpdateDictDown)  { "0" } else { "1" }
} else {
    $InputSchemaType = Read-Host $promptSchemaType
    $InputAllUpdate = Read-Host $promptAllUpdate
    if ($InputAllUpdate -eq "0") {
        $InputSchemaDown = "0"
        $InputGramModel = "0"
        $InputDictDown = "0"
    } else {
        $InputSchemaDown = Read-Host $promptSchemaDown
        $InputGramModel = Read-Host $promptGramModel
        $InputDictDown = Read-Host $promptDictDown
    }
}

if ($InputSchemaType -eq "0") {
    $DictFileSaveDirTableIndex = "base"
} else {
    $DictFileSaveDirTableIndex = "pro"
}

# 根据用户输入的方案号获取下载链接
function Get-ExpectedAssetTypeInfo {
    param(
        [string]$index,
        [hashtable]$keyTable,
        [Object]$releaseObject
    )
    
    $info = $null
    
    foreach ($asset in $releaseObject.assets) {
        if ($Debug) {
            Write-Host "asset.name: $($asset.name)" -ForegroundColor Green
            Write-Host "keyTable[$index]: $($keyTable[$index])" -ForegroundColor Green
        }

        if ($asset.name -match $keyTable[$index]) {
            $info = $asset
            # 打印
            if ($Debug) {
                Write-Host "匹配成功，asset.name: $($asset.name)" -ForegroundColor Green
                Write-Host "目标信息为：$($info)"
            }
            break
        }
    }

    return $info
}

$ExpectedSchemaTypeInfo = Get-ExpectedAssetTypeInfo -index $InputSchemaType -keyTable $KeyTable -releaseObject $SelectedSchemaRelease
$ExpectedDictTypeInfo = Get-ExpectedAssetTypeInfo -index $InputSchemaType -keyTable $KeyTable -releaseObject $SelectedDictRelease
$ExpectedGramTypeInfo = Get-ExpectedAssetTypeInfo -index $GramFileTableIndex -keyTable $GramKeyTable -releaseObject $SelectedGramRelease

if (-not $ExpectedSchemaTypeInfo -or -not $ExpectedDictTypeInfo -or -not $ExpectedGramTypeInfo) {
    if (($InputSchemaDown -eq 0) -and (-not $ExpectedSchemaTypeInfo)) {
        Write-Error "未找到符合条件的方案下载链接"
        Exit-Tip 1
    }
    if (($InputDictDown -eq 0) -and (-not $ExpectedDictTypeInfo)) {
        Write-Error "未找到符合条件的词库下载链接"
        Exit-Tip 1
    }
    if (($InputGramModel -eq 0) -and (-not $ExpectedGramTypeInfo)) {
        Write-Error "未找到符合条件的模型下载链接"
        Exit-Tip 1
    }
}

# 打印
if ($InputSchemaDown -eq "0") {
    Write-Host "下载方案" -ForegroundColor Green
    if ($Debug) {
        Write-Host "最新的辅助码方案下载信息为：$($ExpectedSchemaTypeInfo)" -ForegroundColor Green
    }
}

if ($InputDictDown -eq "0") {
    Write-Host "下载词库" -ForegroundColor Green
    if ($Debug) {
        Write-Host "最新的辅助码词库下载信息为：$($ExpectedDictTypeInfo)" -ForegroundColor Green
    }
}

if ($InputGramModel -eq "0") {
    Write-Host "下载模型" -ForegroundColor Green
    if ($Debug) {
        Write-Host "最新的辅助码模型下载信息为：$($ExpectedGramTypeInfo)" -ForegroundColor Green
    }
}

function Save-TimeRecord {
    param(
        [string]$filePath,
        [string]$key,
        [string]$value
    )
    
    $timeData = @{}
    if (Test-Path $filePath) {
        try {
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $timeData = Get-Content $filePath | ConvertFrom-Json -AsHashtable
            } else {
                $timeData = Get-Content $filePath | ConvertFrom-Json | ForEach-Object {
                    $ht = @{}
                    $_.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                    $ht
                }
            }
        }
        catch {
            Write-Host "警告：无法读取时间记录文件，将创建新的记录" -ForegroundColor Yellow
        }
    }

    $timeData[$key] = $value
    
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $timeData | ConvertTo-Json | Set-Content $filePath
        } else {
            $timeData | ConvertTo-Json -Depth 100 | Set-Content $filePath
        }
    }
    catch {
        Write-Host "错误：无法保存时间记录" -ForegroundColor Red
    }
}

function Get-TimeRecord {
    param(
        [string]$filePath,
        [string]$key
    )
    
    if (Test-Path $filePath) {
        try {
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $timeData = Get-Content $filePath | ConvertFrom-Json -AsHashtable
            } else {
                $json = Get-Content $filePath | ConvertFrom-Json
                $timeData = @{}
                $json.PSObject.Properties | ForEach-Object { $timeData[$_.Name] = $_.Value }
            }
            return $timeData[$key]
        }
        catch {
            Write-Host "警告：无法读取时间记录文件" -ForegroundColor Yellow
        }
    }
    return $null
}

# 比较本地和远程更新时间
function Compare-UpdateTime {
    param(
        [Object]$localTime,
        [datetime]$remoteTime
    )

    if ($null -eq $localTime) {
        Write-Host "本地时间记录不存在，将创建新的时间记录" -ForegroundColor Yellow
        return $true
    }

    $localTime = [datetime]::Parse($localTime)

    if ($null -eq $remoteTime) {
        Write-Host "远程时间记录不存在，无法比较" -ForegroundColor Red
        return $false
    }
    
    if ($remoteTime -gt $localTime) {
        Write-Host "发现新版本，准备更新" -ForegroundColor Yellow
        return $true
    }
    Write-Host "当前已是最新版本" -ForegroundColor Yellow
    return $false
}

# 从JSON文件加载并解析UpdateTimeKey
function Read-UpdateTimeKey {
    param(
        [string]$filePath
    )
    
    if (-not (Test-Path $filePath)) {
        Write-Host "警告：时间记录文件不存在" -ForegroundColor Yellow
        return $null
    }
    
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $timeData = Get-Content $filePath | ConvertFrom-Json -AsHashtable
        } else {
            $json = Get-Content $filePath | ConvertFrom-Json
            $timeData = @{}
            $json.PSObject.Properties | ForEach-Object { $timeData[$_.Name] = $_.Value }
        }
        return $timeData
    }
    catch {
        Write-Host "错误：无法解析JSON文件" -ForegroundColor Red
        return $null
    }
}

# 检查时间记录文件
$hasTimeRecord = Read-UpdateTimeKey -filePath $TimeRecordFile

if (-not $hasTimeRecord) {
    Write-Host "时间记录文件不存在，将创建新的时间记录" -ForegroundColor Yellow
}

# 创建目标目录（如果不存在）
if (-not (Test-Path $targetDir)) {
    Write-Host "创建目标目录: $targetDir" -ForegroundColor Green
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
}

function Test-FileSHA256 {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [Parameter(Mandatory=$true)]
        [string]$CompareSHA256
    )

    if (-not (Test-Path $FilePath)) {
        Write-Host "文件不存在：$FilePath" -ForegroundColor Red
        return $false
    }

    $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
    if ($hash.Hash.ToLower() -eq $CompareSHA256.ToLower()) {
        Write-Host "SHA256 匹配。" -ForegroundColor Green
        return $true
    } else {
        Write-Host "SHA256 不匹配。" -ForegroundColor Red
        Write-Host "文件 SHA256: $($hash.Hash)"
        Write-Host "期望 SHA256: $CompareSHA256"
        return $false
    }
}

# 下载函数
function Save-Asset {
    param(
        [Object]$assetInfo,
        [string]$outFilePath
    )
    
    try {
        if ($UseCnbMirrorSource) {
            $downloadUrl = "https://cnb.cool" + $assetInfo.path
        } else {
            $downloadUrl = $assetInfo.browser_download_url
        }
        
        Write-Host "正在下载文件:$($assetInfo.name)..." -ForegroundColor Green

        if ($UseCurl) {
            curl.exe -L -o $outFilePath --progress-bar $downloadUrl
        } else {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $outFilePath -UseBasicParsing
        }
        Write-Host "下载完成" -ForegroundColor Green

        if ($UseCnbMirrorSource) {
            # 校验文件大小
            $expectedSize = [int64]$assetInfo.size_in_byte
            $actualSize = (Get-Item $outFilePath).Length
            if ($expectedSize -ne $actualSize) {
                Write-Host "文件大小校验失败，删除文件" -ForegroundColor Red
                Write-Host "期望大小: $expectedSize 字节，实际大小: $actualSize 字节" -ForegroundColor Red
                Remove-Item -Path $outFilePath -Force
                Exit-Tip 1
            }
        } else {
            $SHA256 = $assetInfo.digest.Split(":")[1]
            if (-not (Test-FileSHA256 -FilePath $outFilePath -CompareSHA256 $SHA256)) {
                Write-Host "SHA256 校验失败，删除文件" -ForegroundColor Red
                Remove-Item -Path $outFilePath -Force
                Exit-Tip 1
            }
        }
    }
    catch {
        Write-Host "下载失败: $_" -ForegroundColor Red
        Exit-Tip 1
    }
}

# 解压 zip 文件
function Expand-ZipFile {
    param(
        [string]$zipFilePath,
        [string]$destinationPath
    )
 
    try {
        Write-Host "正在解压文件: $zipFilePath" -ForegroundColor Green
        Write-Host "解压到: $destinationPath" -ForegroundColor Green
 
        # --- 获取 7z.exe 路径 ---
        $weaselRootDir = Get-WeaselInstallDir
        if (-not $weaselRootDir) {
            Throw "无法获取小狼毫输入法安装目录，因此无法定位 7z.exe 进行解压。"
        }
        $sevenZipPath = Join-Path $weaselRootDir "7z.exe"
 
        # 检查 7z.exe 是否存在
        if (-not (Test-Path $sevenZipPath -PathType Leaf)) {
            Throw "找不到 7z.exe。预期路径: '$sevenZipPath'。请确认小狼毫输入法安装正常且包含 7z.exe"
        }
        Write-Host "已找到 7z.exe：$sevenZipPath" -ForegroundColor DarkCyan
 
        # --- 确保目标目录存在 ---
        if (-not (Test-Path $destinationPath)) {
            try {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
                Write-Host "已创建目标目录: $destinationPath" -ForegroundColor Yellow
            }
            catch {
                Throw "创建目标目录 '$destinationPath' 失败: $($_.Exception.Message)。"
            }
        }
 
        # --- 调用 7z.exe 进行解压 ---
        $arguments = "x `"$zipFilePath`" -o`"$destinationPath`" -y"
        Write-Host "正在调用 7-Zip 进行解压..." -ForegroundColor DarkGreen
 
        $process = Start-Process -FilePath $sevenZipPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
      
        if ($process.ExitCode -ne 0) {
            Throw "7-Zip 解压失败，退出代码: $($process.ExitCode)。"
        }
      
        Write-Host "解压完成" -ForegroundColor Green
    }
    catch {
        Write-Host "解压失败: $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item -Path $zipFilePath -Force -ErrorAction SilentlyContinue
        Exit-Tip 1
    }
}

if ($SkipStopWeasel) {
    Write-Host "所设置的部署目录与小狼毫配置的用户目录不同，跳过小狼毫服务停止操作" -ForegroundColor Red
} elseif ($InputSchemaDown -eq "0" -or $InputDictDown -eq "0" -or $InputGramModel -eq "0") {
    # 开始更新词库，从现在开始不要操作键盘，直到更新完成，否则会触发小狼毫重启，文件更新告警，导致更新失败，请放心更新完成后会自动拉起小狼毫
    Write-Host "正在更新词库，请不要操作键盘，直到更新完成" -ForegroundColor Red
    Write-Host "更新完成后会自动拉起小狼毫" -ForegroundColor Red
} else {
    Write-Host "没有指定要更新的内容，将退出" -ForegroundColor Red
    Exit-Tip 0
}

function Get-UpdateAtObj {
    param (
        [object]$assetInfo
    )
    return $assetInfo.updated_at
}

$UpdateFlag = $false

if ($InputSchemaDown -eq "0") {
    # 下载方案
    $SchemaUpdateTimeKey = $KeyTable[$InputSchemaType] + "_schema_update_time"
    $SchemaUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $SchemaUpdateTimeKey
    $SchemaRemoteTime = [datetime]::Parse($(Get-UpdateAtObj -assetInfo $ExpectedSchemaTypeInfo))
    Write-Host "正在检查方案是否需要更新..." -ForegroundColor Yellow
    Write-Host "本地时间: $SchemaUpdateTime" -ForegroundColor Green
    Write-Host "远程时间: $SchemaRemoteTime" -ForegroundColor Green
    if (Compare-UpdateTime -localTime $SchemaUpdateTime -remoteTime $SchemaRemoteTime) {
        $UpdateFlag = $true
        Write-Host "正在下载方案..." -ForegroundColor Green
        Save-Asset -assetInfo $ExpectedSchemaTypeInfo -outFilePath $tempSchemaZip
        Write-Host "正在解压方案..." -ForegroundColor Green
        Expand-ZipFile -zipFilePath $tempSchemaZip -destinationPath $SchemaExtractPath
        Write-Host "正在复制文件..." -ForegroundColor Green
        # 方案里面没有子文件夹，直接复制到目标目录
        $sourceDir = $SchemaExtractPath
        if (-not (Test-Path $sourceDir)) {
            Write-Host "错误：压缩包中未找到 $sourceDir 目录" -ForegroundColor Red
            # 保留下载的 zip 以便后续检查或手动处理，仍然清理解压目录
            Remove-Item -Path $SchemaExtractPath -Recurse -Force
            Exit-Tip 1
        }
        Stop-WeaselServer
        # 等待1秒
        Start-Sleep -Seconds 1
        Get-ChildItem -Path $sourceDir -Recurse | ForEach-Object {
            # Write-Host "SkipFiles: $SkipFiles"
            if (Test-SkipFile -filePath $_.Name) {
                Write-Host "跳过文件: $($_.Name)" -ForegroundColor Yellow
            } else {
                # $relativePath = Resolve-Path -path $_.FullName -RelativeBasePath $sourceDir -Relative
                $relativePath = $_.FullName.Substring($sourceDir.Length)
                # 去掉可能的开头的 .\ 或 ./，否则 Join-Path 会产生包含 \\.\ 的路径
                # 使用正则替换以避免 TrimStart 在传入 '\\' 时的类型错误
                $relativePath = $relativePath -replace '^[.][\\/]+',''
                $destinationPath = Join-Path $targetDir $relativePath
                $destinationDir = [System.IO.Path]::GetDirectoryName($destinationPath)
                if (-not (Test-Path $destinationDir)) {
                    New-Item -ItemType Directory -Path $destinationDir | Out-Null
                }
                if (Test-Path $_.FullName -PathType Container) {
                    
                } elseif (Test-Path $_.FullName -PathType Leaf) {
                    Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                    if ($Debug) {
                        Write-Host "正在复制文件: $($_.Name)" -ForegroundColor Green
                        Write-Host "相对路径: $relativePath" -ForegroundColor Green
                        Write-Host "目标路径: $destinationPath" -ForegroundColor Green
                    }
                }
            }
        }

        # 将现在的本地时间记录到JSON文件
        Save-TimeRecord -filePath $TimeRecordFile -key $SchemaUpdateTimeKey -value $SchemaRemoteTime
        # 清理解压目录（保留下载的 zip）
        Remove-Item -Path $SchemaExtractPath -Recurse -Force
    }
}

if ($InputDictDown -eq "0") {
    # 下载词库
    $DictUpdateTimeKey = $KeyTable[$InputSchemaType] + "_dict_update_time"
    $DictUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $DictUpdateTimeKey
    $DictRemoteTime = [datetime]::Parse($(Get-UpdateAtObj -assetInfo $ExpectedDictTypeInfo))
    Write-Host "正在检查词库是否需要更新..." -ForegroundColor Yellow
    Write-Host "本地时间: $DictUpdateTime" -ForegroundColor Green
    Write-Host "远程时间: $DictRemoteTime" -ForegroundColor Green
    if (Compare-UpdateTime -localTime $DictUpdateTime -remoteTime $DictRemoteTime) {
        $UpdateFlag = $true
        Write-Host "正在下载词库..." -ForegroundColor Green
        Save-Asset -assetInfo $ExpectedDictTypeInfo -outFilePath $tempDictZip
        Write-Host "正在解压词库..." -ForegroundColor Green
        Expand-ZipFile -zipFilePath $tempDictZip -destinationPath $DictExtractPath
        Write-Host "正在复制文件..." -ForegroundColor Green
        $sourceDir = Get-DictExtractedFolderPath -extractPath $DictExtractPath -assetName $KeyTable[$InputSchemaType]
        if (-not (Test-Path $sourceDir)) {
            Write-Host "错误：压缩包中未找到 $sourceDir 目录" -ForegroundColor Red
            Remove-Item -Path $DictExtractPath -Force -Recurse
            Exit-Tip 1
        }
        Stop-WeaselServer
        # 等待1秒
        Start-Sleep -Seconds 1
        if (-not (Test-Path -Path $(Join-Path $targetDir $DictFileSaveDirTable[$DictFileSaveDirTableIndex]))){
            New-Item -ItemType Directory -Path $(Join-Path $targetDir $DictFileSaveDirTable[$DictFileSaveDirTableIndex]) | Out-Null
        }
        Get-ChildItem -Path $sourceDir | ForEach-Object {
            if ($Debug) {
                Write-Host "正在复制文件: $($_.Name)" -ForegroundColor Green
            }
            if (Test-SkipFile -filePath $_.Name) {
                Write-Host "跳过文件: $($_.Name)" -ForegroundColor Yellow
            } else {
                Copy-Item -Path $_.FullName -Destination $(Join-Path $targetDir $DictFileSaveDirTable[$DictFileSaveDirTableIndex]) -Recurse -Force
            }
        }

        # 将现在的本地时间记录到JSON文件
        Save-TimeRecord -filePath $TimeRecordFile -key $DictUpdateTimeKey -value $DictRemoteTime -isDict $true
        # 清理临时文件
        Remove-Item -Path $DictExtractPath -Recurse -Force
    }
}

function Update-GramModel {
    Write-Host "正在下载模型..." -ForegroundColor Green
    Save-Asset -assetInfo $ExpectedGramTypeInfo -outFilePath $tempGram
    Write-Host "正在复制文件..." -ForegroundColor Green

    Stop-WeaselServer
    # 等待1秒
    Start-Sleep -Seconds 1
    Copy-Item -Path $tempGram -Destination $targetDir -Force
    # 将现在的本地时间记录到JSON文件
    Save-TimeRecord -filePath $TimeRecordFile -key $GramUpdateTimeKey -value $GramRemoteTime
    # 清理临时文件
    Remove-Item -Path $tempGram -Force
}

if ($InputGramModel -eq "0") {
    # 下载模型
    $GramUpdateTimeKey = $GramReleaseTag + "_gram_update_time"
    $GramUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $GramUpdateTimeKey
    $GramRemoteTime = [datetime]::Parse($(Get-UpdateAtObj -assetInfo $ExpectedGramTypeInfo))
    Write-Host "正在检查模型是否需要更新..." -ForegroundColor Yellow
    # 检查目标文件 $targetDir/$tempGram 是否存在
    $filePath = Join-Path $targetDir $GramModelFileName
    if ($Debug) {
        Write-Host "模型文件路径: $filePath" -ForegroundColor Green
    }
    Write-Host "本地时间: $GramUpdateTime" -ForegroundColor Green
    Write-Host "远程时间: $GramRemoteTime" -ForegroundColor Green
    if (Compare-UpdateTime -localTime $GramUpdateTime -remoteTime $GramRemoteTime) {
        Update-GramModel
        $UpdateFlag = $true
    } elseif (Test-Path -Path $filePath) {
        if ($UseCnbMirrorSource) {
            # 校验文件大小
            $expectedSize = [int64]$ExpectedGramTypeInfo.size_in_byte
            $actualSize = (Get-Item $filePath).Length
            if ($expectedSize -ne $actualSize) {
                Write-Host "文件大小校验失败，需要更新" -ForegroundColor Red
                Write-Host "期望大小: $expectedSize 字节，实际大小: $actualSize 字节" -ForegroundColor Red
                Remove-Item -Path $filePath -Force
                Update-GramModel
                $UpdateFlag = $true
            }
        } else {
            # 计算目标文件的SHA256
            $localSHA256 = (Get-FileHash $filePath -Algorithm SHA256).Hash.ToLower()
            # 计算远程文件的SHA256
            $remoteSHA256 = $ExpectedGramTypeInfo.digest.Split(":")[1].ToLower()
            # 比较SHA256
            if ($localSHA256 -ne $remoteSHA256) {
                Write-Host "模型SHA256不匹配，需要更新" -ForegroundColor Red
                Update-GramModel
                $UpdateFlag = $true
            }
        }
    } else {
        Write-Host "模型不存在，需要更新" -ForegroundColor Red
        Update-GramModel
    }
}

if ($UpdateFlag) {
    if ($disableAutoReDeploy) {
        Write-Host "跳过触发重新部署" -ForegroundColor Yellow
    } elseif (-not $SkipStopWeasel) {
        Start-WeaselServer
        # 等待1秒
        Start-Sleep -Seconds 1
        Write-Host "内容更新，触发小狼毫重新部署..." -ForegroundColor Green
        Start-WeaselReDeploy
    }
}

if ($UpdateFlag) {
    Write-Host "操作已完成！文件已部署到 Weasel 配置目录:$($targetDir)" -ForegroundColor Green
} else {
    Write-Host "操作已完成！恭喜你! 所有文件都是最新的不需要更新 " -ForegroundColor Green
}

Exit-Tip 0
