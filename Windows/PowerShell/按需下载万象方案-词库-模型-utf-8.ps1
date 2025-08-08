############# 自动更新配置项，配置好后将 AutoUpdate 设置为 true 即可 #############
$AutoUpdate = $false

# 是否使用镜像源，如果设置为 $true，则从 CNB 获取资源；否则从 GitHub 获取。
$UseMirrorSource = $true

# 设置自动更新时，是否更新方案、词库、模型，不想更新某项就改成false
$IsUpdateSchemaDown = $true
$IsUpdateDictDown = $true
$IsUpdateModel = $true

# 设置自动更新时选择的方案，注意必须包含双引号，例如：$InputSchemaType = "0"
# [0]-基础版; [1]-小鹤; [2]-汉心; [3]-简单鹤; [4]-墨奇; [5]-虎码; [6]-五笔; [7]-自然码
$InputSchemaType = "7"

# 设置自动更新时要跳过的文件列表，配置好后删除注释符号
#$SkipFiles = @(
#     "wanxiang_en.dict.yaml",
#     "tone_fallback.lua",
#     "custom_phrase.txt"
#);

# 设置代理地址和端口，配置好后删除注释符号
#$proxyAddress = "http://127.0.0.1:7897"
#[System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxyAddress)
#[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

# 设置GitHub Token请求头，防止api请求失败403错误，配置好后删除注释符号
$env:GITHUB_TOKEN = "这里输入你的Token"    #打开链接https://github.com/settings/tokens，注册一个token(Public repositories) 

############# 自动更新配置项，配置好后将 AutoUpdate 设置为 true 即可 #############

$UpdateToolsVersion = "DEFAULT_UPDATE_TOOLS_VERSION_TAG";
if ($UpdateToolsVersion.StartsWith("DEFAULT")) {
    Write-Host "您下载的是非发行版脚本，请勿直接使用，请去 releases 页面下载最新版本：https://github.com/expoli/rime-wanxiang-update-tools/releases" -ForegroundColor Yellow;
} else {
    Write-Host "当前更新工具版本：$UpdateToolsVersion" -ForegroundColor Yellow;
}

# 设置 GitHub 仓库所有者和名称
$SchemaOwner = "amzxyz"
$SchemaRepo = "rime_wanxiang"
$GramRepo = "RIME-LMDG"
$GramReleaseTag = "LTS"
$GramModelFileName = "wanxiang-lts-zh-hans.gram"
$ReleaseTimeRecordFile = "release_time_record.json"
$UpdateToolsOwner = "expoli"
$UpdateToolsRepo = "rime-wanxiang-update-tools"
# 定义临时文件路径
$tempSchemaZip = Join-Path $env:TEMP "wanxiang_schema_temp.zip"
$tempDictZip = Join-Path $env:TEMP "wanxiang_dict_temp.zip"
$tempGram = Join-Path $env:TEMP "wanxiang-lts-zh-hans.gram"
$tempGramMd5 = Join-Path $env:TEMP "wanxiang-lts-zh-hans.gram.md5"
$SchemaExtractPath = Join-Path $env:TEMP "wanxiang_schema_extract"
$DictExtractPath = Join-Path $env:TEMP "wanxiang_dict_extract"

# 设置 CNB 镜像源的仓库和标签
$CnbOwner = "amzxyz"
$CnbSchemaRepo = "rime-wanxiang"
$CnbDictTag = "v1.0.0"
$CnbGramTag = "model" 

$Debug = $false;

# 方案编号映射表
$KeyTable = @{
    "0" = "base";
    "1" = "flypy";
    "2" = "hanxin";
    "3" = "jdh";
    "4" = "moqi";
    "5" = "tiger";
    "6" = "wubi";
    "7" = "zrm";
}

# CNB 词库镜像源文件名映射表
$CnbDictFilenameMap = @{
    "moqi"   = "1-pro-moqi-fuzhu-dicts.zip";
    "flypy"  = "2-pro-flypy-fuzhu-dicts.zip";
    "zrm"    = "3-pro-zrm-fuzhu-dicts.zip";
    "jdh"    = "4-pro-jdh-fuzhu-dicts.zip" ;
    "tiger"  = "5-pro-tiger-fuzhu-dicts.zip";
    "wubi"   = "6-pro-wubi-fuzhu-dicts.zip";
    "hanxin" = "7-pro-hanxin-fuzhu-dicts.zip";
    "base"   = "9-base-dicts.zip";
}

$SchemaDownloadTip = "[0]-基础版; [1]-小鹤; [2]-汉心; [3]-简单鹤; [4]-墨奇; [5]-虎码; [6]-五笔; [7]-自然码";

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

function Exit-Tip {
    param(
        [string]$exitCode = 0
    )
    Write-Host '按任意键退出...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit $exitCode
}

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
    return $SkipFiles -contains $filePath
}

# 调用函数并赋值给变量
$rimeUserDir = Get-WeaselUserDir
$rimeInstallDir = Get-WeaselInstallDir
$rimeServerExecutable = Get-WeaselServerExecutable

function Stop-WeaselServer {
    if (-not $rimeServerExecutable) {
        Write-Host "警告：未找到Weasel服务端可执行程序，请确保已正确安装小狼毫输入法" -ForegroundColor Yellow
        Exit-Tip 1
    }
    Start-Process -FilePath (Join-Path $rimeInstallDir $rimeServerExecutable) -ArgumentList '/q'
}

function Start-WeaselServer {
    if (-not $rimeServerExecutable) {
        Write-Host "警告：未找到Weasel服务端可执行程序，请确保已正确安装小狼毫输入法" -ForegroundColor Yellow
        Exit-Tip 1
    }
    Start-Process -FilePath (Join-Path $rimeInstallDir $rimeServerExecutable)
}

function Start-WeaselReDeploy{
    $defaultShortcutPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\小狼毫输入法\【小狼毫】重新部署.lnk"
    if (Test-Path -Path $defaultShortcutPath) {
        Write-Host "找到默认【小狼毫】重新部署快捷方式，将执行" -ForegroundColor Green
        Invoke-Item -Path $defaultShortcutPath
    }
    else {
        Write-Host "未找到默认的【小狼毫】重新部署快捷方式，将尝试执行默认的重新部署命令" -ForegroundColor Yellow
        Write-Host "跳过触发重新部署" -ForegroundColor Yellow
    }
}

# 检查必要路径是否为空
if (-not $rimeUserDir -or -not $rimeInstallDir -or -not $rimeServerExecutable) {
    Write-Host "错误：无法获取Weasel必要路径，请检查输入法是否正确安装" -ForegroundColor Red
    Exit-Tip 1
}
Write-Host "Weasel用户目录路径为: $rimeUserDir"
$targetDir = $rimeUserDir
$TimeRecordFile = Join-Path $targetDir $ReleaseTimeRecordFile

# CNB: 从网页HTML中提取 __NEXT_DATA__ 的JSON内容
function Get-CnbReleaseData {
    param(
        [string]$pageUrl
    )
    try {
        Write-Host "正在从 CNB 页面获取信息: $pageUrl" -ForegroundColor Cyan
        $htmlContent = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing | Select-Object -ExpandProperty Content
      
        # 使用正则表达式匹配<script id="__NEXT_DATA__">标签内的内容
        $regex = '(?s)<script id="__NEXT_DATA__"[^>]*>(.*?)</script>'
        if ($htmlContent -match $regex) {
            $jsonData = $matches[1]
            return $jsonData | ConvertFrom-Json
        } else {
            Write-Host "错误：在页面中未找到 '__NEXT_DATA__' JSON 数据。" -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "错误：下载或解析CNB页面失败: $pageUrl" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $null
    }
}

# CNB: 简化版下载函数 (无SHA校验)
function Download-FileFromUrl {
    param(
        [string]$url,
        [string]$outFilePath,
        [string]$fileName
    )
    try {
        Write-Host "正在下载文件: $fileName..." -ForegroundColor Green
        Write-Host "URL: $url" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $url -OutFile $outFilePath -UseBasicParsing
        Write-Host "下载完成" -ForegroundColor Green
    }
    catch {
        Write-Host "下载失败: $_" -ForegroundColor Red
        Exit-Tip 1
    }
}

function Test-VersionSuffix {
    param(
        [string]$url
    )
    # tag_name = v1.0.0 or v1.0
    $pattern = 'v(\d+)(\.\d+)+'
    return $url -match $pattern
}

function Test-DictSuffix {
    param(
        [string]$url
    )

    # tag_name = dict-nightly
    $pattern = 'dict-nightly'
    return $url -match $pattern
}

function Get-ReleaseInfo {
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
        Exit-Tip 1
    }

    # 检查是否有可下载资源
    if ($response.assets.Count -eq 0) {
        Write-Error "该版本没有可下载资源"
        Exit-Tip 1
    }
    return $response
}

# 无论是否使用镜像，脚本自身更新总是检查GitHub
Write-Host "正在检查更新工具是否有新版本..." -ForegroundColor Cyan
try {
    $UpdateTollsResponse = Get-ReleaseInfo -owner $UpdateToolsOwner -repo $UpdateToolsRepo
    if ($UpdateTollsResponse.Count -gt 0) {
        # 过滤掉包含 -rc 的 tag_name
        $StableUpdateToolsReleases = $UpdateTollsResponse | Where-Object { $_.tag_name -notmatch '-rc' }
        if ($StableUpdateToolsReleases.Count -eq 0) {
            Write-Host "没有找到稳定版的更新工具版本信息" -ForegroundColor Yellow
        } else {
            $LatestUpdateToolsRelease = $StableUpdateToolsReleases | Select-Object -First 1
            if ($LatestUpdateToolsRelease.tag_name -ne $UpdateToolsVersion) {
                Write-Host "发现新版本的更新工具: $($LatestUpdateToolsRelease.tag_name)" -ForegroundColor Yellow
                Write-Host "如需更新,请访问 https://github.com/expoli/rime-wanxiang-update-tools/releases 下载最新版本" -ForegroundColor Yellow
                Write-Host "当前版本: $UpdateToolsVersion" -ForegroundColor Yellow
                Write-Host "更新日志: $($LatestUpdateToolsRelease.body)" -ForegroundColor Yellow
            }
        }
    } else {
         Write-Host "没有找到更新工具的版本信息。" -ForegroundColor Yellow
    }
} catch {
    Write-Host "检查工具更新失败，可能是网络问题。将继续执行..." -ForegroundColor Yellow
}

$promptSchemaType = "请选择你要下载的方案类型的编号: `n$SchemaDownloadTip"
$promptAllUpdate = "是否更新所有内容（方案、词库、模型）:`n[0]-更新所有; [1]-不更新所有"
$promptSchemaDown = "是否下载方案:`n[0]-下载; [1]-不下载"
$promptGramModel = "是否下载模型:`n[0]-下载; [1]-不下载"
$promptDictDown = "是否下载词库:`n[0]-下载; [1]-不下载"

if (-not $Debug) {
    if ($AutoUpdate) {
        Write-Host "自动更新模式，将自动下载最新的版本" -ForegroundColor Green
        Write-Host "你配置的方案号为：$InputSchemaType" -ForegroundColor Green
        # 方案号只支持0-7
        if ($InputSchemaType -lt 0 -or $InputSchemaType -gt 7) {
            Write-Error "错误：方案号只能是0-7"
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
} else {
    $InputSchemaType = "7"
    $InputSchemaDown = "0"
    $InputGramModel = "0"
    $InputDictDown = "0"
}

if ($InputSchemaType -eq "0") {
    $DictFileSaveDirTableIndex = "base"
} else {
    $DictFileSaveDirTableIndex = "pro"
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

function Download-Files {
    param(
        [Object]$assetInfo,
        [string]$outFilePath
    )
  
    try {
        $downloadUrl = $assetInfo.browser_download_url
        Write-Host "正在下载文件:$($assetInfo.name)..." -ForegroundColor Green
        Invoke-WebRequest -Uri $downloadUrl -OutFile $outFilePath -UseBasicParsing
        Write-Host "下载完成" -ForegroundColor Green
        $SHA256 = $assetInfo.digest.Split(":")[1]
        if (-not (Test-FileSHA256 -FilePath $outFilePath -CompareSHA256 $SHA256)) {
            Write-Host "SHA256 校验失败，删除文件" -ForegroundColor Red
            Remove-Item -Path $outFilePath -Force
            Exit-Tip 1
        }
    }
    catch {
        Write-Host "下载失败: $_" -ForegroundColor Red
        Exit-Tip 1
    }
}

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

# 通过 UseMirrorSource 开关分离 GitHub 和 CNB 的逻辑
if ($UseMirrorSource) {
    #############################################
    #           CNB 镜像源更新逻辑            #
    #############################################
    Write-Host "正在使用 CNB 镜像源进行更新..." -ForegroundColor Magenta

    if ($InputSchemaDown -eq "0" -or $InputDictDown -eq "0" -or $InputGramModel -eq "0") {
        Write-Host "正在更新，请不要操作键盘，直到更新完成。更新后会自动拉起小狼毫。" -ForegroundColor Red
    } else {
        Write-Host "没有指定要更新的内容，将退出" -ForegroundColor Red
        Exit-Tip 0
    }

    $UpdateFlag = $false

    # 1. 更新方案 (Schema)
    if ($InputSchemaDown -eq "0") {
        Write-Host "--- 正在检查方案(Schema)更新 ---" -ForegroundColor Yellow
        $luaUrl = "https://cnb.cool/$CnbOwner/$CnbSchemaRepo/-/git/raw/wanxiang/lua/wanxiang.lua"
        $luaContent = Invoke-WebRequest -Uri $luaUrl -UseBasicParsing | Select-Object -ExpandProperty Content
      
        $remoteSchemaTag = $null
        if ($luaContent -match 'wanxiang\.version = "(.*?)"') {
            $remoteSchemaTag = $matches[1]
            Write-Host "从wanxiang.lua获取到远程方案版本: $remoteSchemaTag" -ForegroundColor Green
        } else {
            Write-Host "错误：无法从 $luaUrl 中获取方案版本号。" -ForegroundColor Red
            Exit-Tip 1
        }
      
        $schemaPageUrl = "https://cnb.cool/$CnbOwner/$CnbSchemaRepo/-/releases/tag/$remoteSchemaTag"
        $cnbSchemaData = Get-CnbReleaseData -pageUrl $schemaPageUrl
      
        if ($cnbSchemaData) {
            $assetBaseName = "rime-wanxiang-" + $KeyTable[$InputSchemaType]
            if ($KeyTable[$InputSchemaType] -ne "base") {
                $assetBaseName += "-fuzhu"
            }
            $targetSchemaFileName = $assetBaseName + ".zip"

            $schemaAsset = $cnbSchemaData.props.pageProps.releasesDetailData.release.assets | Where-Object { $_.name -eq $targetSchemaFileName } | Select-Object -First 1
          
            if ($schemaAsset) {
                $SchemaUpdateTimeKey = $KeyTable[$InputSchemaType] + "_schema_update_time"
                $SchemaUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $SchemaUpdateTimeKey
                $SchemaRemoteTime = [datetime]::Parse($schemaAsset.updatedAt)
              
                Write-Host "本地记录时间: $SchemaUpdateTime" -ForegroundColor Green
                Write-Host "远程文件时间: $SchemaRemoteTime" -ForegroundColor Green

                if (Compare-UpdateTime -localTime $SchemaUpdateTime -remoteTime $SchemaRemoteTime) {
                    $UpdateFlag = $true
                    $downloadUrl = "https://cnb.cool/$CnbOwner/$CnbSchemaRepo/-/releases/download/$remoteSchemaTag/$($schemaAsset.name)"
                    Download-FileFromUrl -url $downloadUrl -outFilePath $tempSchemaZip -fileName $schemaAsset.name
                    Expand-ZipFile -zipFilePath $tempSchemaZip -destinationPath $SchemaExtractPath
                  
                    Stop-WeaselServer; Start-Sleep -Seconds 1
                  
                    Get-ChildItem -Path $SchemaExtractPath -Recurse | ForEach-Object {
                        if ($_.Name -notin $SkipFiles) {
                            $relativePath = $_.FullName.Substring($SchemaExtractPath.Length)
                            $destinationPath = Join-Path $targetDir $relativePath
                            if (Test-Path $_.FullName -PathType Leaf) {
                                Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                            }
                        } else { Write-Host "跳过文件: $($_.Name)" -ForegroundColor Yellow }
                    }
                  
                    Save-TimeRecord -filePath $TimeRecordFile -key $SchemaUpdateTimeKey -value $SchemaRemoteTime
                    Remove-Item -Path $tempSchemaZip, $SchemaExtractPath -Recurse -Force
                }
            } else { Write-Host "错误: 在CNB页面上未找到方案文件 $targetSchemaFileName" -ForegroundColor Red }
        }
    }

    # 2. 更新词库 (Dict)
    if ($InputDictDown -eq "0") {
        Write-Host "--- 正在检查词库(Dict)更新 ---" -ForegroundColor Yellow
        $dictPageUrl = "https://cnb.cool/$CnbOwner/$CnbSchemaRepo/-/releases/tag/$CnbDictTag"
        $cnbDictData = Get-CnbReleaseData -pageUrl $dictPageUrl

        if ($cnbDictData) {
            $targetDictFileName = $CnbDictFilenameMap[$KeyTable[$InputSchemaType]]
            $dictAsset = $cnbDictData.props.pageProps.releasesDetailData.release.assets | Where-Object { $_.name -eq $targetDictFileName } | Select-Object -First 1

            if ($dictAsset) {
                $DictUpdateTimeKey = $KeyTable[$InputSchemaType] + "_dict_update_time"
                $DictUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $DictUpdateTimeKey
                $DictRemoteTime = [datetime]::Parse($dictAsset.updatedAt)

                Write-Host "本地记录时间: $DictUpdateTime" -ForegroundColor Green
                Write-Host "远程文件时间: $DictRemoteTime" -ForegroundColor Green

                if (Compare-UpdateTime -localTime $DictUpdateTime -remoteTime $DictRemoteTime) {
                    $UpdateFlag = $true
                    $downloadUrl = "https://cnb.cool/$CnbOwner/$CnbSchemaRepo/-/releases/download/$CnbDictTag/$($dictAsset.name)"
                    Download-FileFromUrl -url $downloadUrl -outFilePath $tempDictZip -fileName $dictAsset.name
                    Expand-ZipFile -zipFilePath $tempDictZip -destinationPath $DictExtractPath
                  
                    $sourceDir = Get-DictExtractedFolderPath -extractPath $DictExtractPath -assetName $KeyTable[$InputSchemaType]
                  
                    Stop-WeaselServer; Start-Sleep -Seconds 1
                  
                    $dictTargetDir = Join-Path $targetDir $DictFileSaveDirTable[$DictFileSaveDirTableIndex]
                    if (-not (Test-Path -Path $dictTargetDir)){ New-Item -ItemType Directory -Path $dictTargetDir | Out-Null }
                  
                    Get-ChildItem -Path $sourceDir | ForEach-Object {
                         if (-not (Test-SkipFile -filePath $_.Name)) {
                            Copy-Item -Path $_.FullName -Destination $dictTargetDir -Recurse -Force
                         } else { Write-Host "跳过文件: $($_.Name)" -ForegroundColor Yellow }
                    }

                    Save-TimeRecord -filePath $TimeRecordFile -key $DictUpdateTimeKey -value $DictRemoteTime
                    Remove-Item -Path $tempDictZip, $DictExtractPath -Recurse -Force
                }
            } else { Write-Host "错误: 在CNB页面上未找到词库文件 $targetDictFileName" -ForegroundColor Red }
        }
    }

    # 3. 更新模型 (Gram)
    if ($InputGramModel -eq "0") {
        Write-Host "--- 正在检查模型(Gram)更新 ---" -ForegroundColor Yellow
        $gramPageUrl = "https://cnb.cool/$CnbOwner/$CnbSchemaRepo/-/releases/tag/$CnbGramTag"
        $cnbGramData = Get-CnbReleaseData -pageUrl $gramPageUrl

        if ($cnbGramData) {
            $gramAsset = $cnbGramData.props.pageProps.releasesDetailData.release.assets | Where-Object { $_.name -eq $GramModelFileName } | Select-Object -First 1

            if ($gramAsset) {
                $GramUpdateTimeKey = $CnbGramTag + "_gram_update_time" # Use a consistent key
                $GramUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $GramUpdateTimeKey
                $GramRemoteTime = [datetime]::Parse($gramAsset.updatedAt)
              
                Write-Host "本地记录时间: $GramUpdateTime" -ForegroundColor Green
                Write-Host "远程文件时间: $GramRemoteTime" -ForegroundColor Green

                if (Compare-UpdateTime -localTime $GramUpdateTime -remoteTime $GramRemoteTime) {
                    $UpdateFlag = $true
                    $downloadUrl = "https://cnb.cool/$CnbOwner/$CnbSchemaRepo/-/releases/download/$CnbGramTag/$($gramAsset.name)"
                    Download-FileFromUrl -url $downloadUrl -outFilePath $tempGram -fileName $gramAsset.name
                  
                    Stop-WeaselServer; Start-Sleep -Seconds 1
                    Copy-Item -Path $tempGram -Destination $targetDir -Force
                  
                    Save-TimeRecord -filePath $TimeRecordFile -key $GramUpdateTimeKey -value $GramRemoteTime
                    Remove-Item -Path $tempGram -Force
                }

            } else { Write-Host "错误: 在CNB页面上未找到模型文件 $GramModelFileName" -ForegroundColor Red }
        }
    }

} else {
    #############################################
    #           GitHub API 更新逻辑              #
    #############################################
    Write-Host "正在使用 GitHub API 进行更新..." -ForegroundColor Magenta

    # 获取最新的版本信息
    $SchemaResponse = Get-ReleaseInfo -owner $SchemaOwner -repo $SchemaRepo
    $GramResponse = Get-ReleaseInfo -owner $SchemaOwner -repo $GramRepo

    $SelectedDictRelease = $null
    $SelectedSchemaRelease = $null
    $SelectedGramRelease = $null

    foreach ($release in $SchemaResponse) {
        if (($null -eq $SelectedDictRelease) -and (Test-DictSuffix -url $release.tag_name)) {
            $SelectedDictRelease = $release
        }
        if ((Test-VersionSuffix -url $release.tag_name) -and (-not $SelectedSchemaRelease)) {
            $SelectedSchemaRelease = $release
        }
        if ($SelectedDictRelease -and $SelectedSchemaRelease) {
            break
        }
    }

    foreach ($release in $GramResponse) {
        if ($Debug) {
            Write-Host "release.tag_name: $($release.tag_name)" -ForegroundColor Green
            Write-Host "GramReleaseTag: $GramReleaseTag" -ForegroundColor Green
        }
        if ($release.tag_name -eq $GramReleaseTag) {
            $SelectedGramRelease = $release
        }
    }

    if ($SelectedDictRelease -and $SelectedSchemaRelease -and $SelectedGramRelease) {
        Write-Host "解析出最新的词库链接为：$($SelectedDictRelease.html_url)" -ForegroundColor Green
        Write-Host "解析出最新的版本链接为：$($SelectedSchemaRelease.html_url)" -ForegroundColor Green
        Write-Host "解析出最新的模型链接为：$($SelectedGramRelease.html_url)" -ForegroundColor Green
    } else {
        Write-Error "未找到符合条件的版本或词库链接"
        Exit-Tip 1
    }

    Write-Host "方案最新的版本为：$($SelectedSchemaRelease.tag_name)"
    Write-Host "方案更新日志: " -ForegroundColor Yellow
    Write-Host $SelectedSchemaRelease.body -ForegroundColor Yellow

    function Get-ExpectedAssetTypeInfo {
        param(
            [string]$index,
            [hashtable]$keyTable,
            [Object]$releaseObject
        )
        $info = $null
        foreach ($asset in $releaseObject.assets) {
            if ($asset.name -match $keyTable[$index]) {
                $info = $asset; break
            }
        }
        return $info
    }

    $ExpectedSchemaTypeInfo = Get-ExpectedAssetTypeInfo -index $InputSchemaType -keyTable $KeyTable -releaseObject $SelectedSchemaRelease
    $ExpectedDictTypeInfo = Get-ExpectedAssetTypeInfo -index $InputSchemaType -keyTable $KeyTable -releaseObject $SelectedDictRelease
    $ExpectedGramTypeInfo = Get-ExpectedAssetTypeInfo -index $GramFileTableIndex -keyTable $GramKeyTable -releaseObject $SelectedGramRelease

    if ((-not $ExpectedSchemaTypeInfo -and $InputSchemaDown -eq "0") -or `
        (-not $ExpectedDictTypeInfo -and $InputDictDown -eq "0") -or `
        (-not $ExpectedGramTypeInfo -and $InputGramModel -eq "0")) {
        Write-Error "未找到符合条件的一个或多个下载链接"
        Exit-Tip 1
    }

    if ($InputSchemaDown -eq "0" -or $InputDictDown -eq "0" -or $InputGramModel -eq "0") {
        Write-Host "正在更新，请不要操作键盘，直到更新完成。更新后会自动拉起小狼毫。" -ForegroundColor Red
    } else {
        Write-Host "没有指定要更新的内容，将退出" -ForegroundColor Red
        Exit-Tip 0
    }

    $UpdateFlag = $false

    if ($InputSchemaDown -eq "0") {
        # 下载方案
        $SchemaUpdateTimeKey = $KeyTable[$InputSchemaType] + "_schema_update_time"
        $SchemaUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $SchemaUpdateTimeKey
        $SchemaRemoteTime = [datetime]::Parse($ExpectedSchemaTypeInfo.updated_at)
        Write-Host "正在检查方案是否需要更新..." -ForegroundColor Yellow
        Write-Host "本地时间: $SchemaUpdateTime" -ForegroundColor Green
        Write-Host "远程时间: $SchemaRemoteTime" -ForegroundColor Green
        if (Compare-UpdateTime -localTime $SchemaUpdateTime -remoteTime $SchemaRemoteTime) {
            $UpdateFlag = $true
            Download-Files -assetInfo $ExpectedSchemaTypeInfo -outFilePath $tempSchemaZip
            Expand-ZipFile -zipFilePath $tempSchemaZip -destinationPath $SchemaExtractPath
          
            Stop-WeaselServer; Start-Sleep -Seconds 1
            Get-ChildItem -Path $SchemaExtractPath -Recurse | ForEach-Object {
                if ($_.Name -notin $SkipFiles) {
                    $relativePath = $_.FullName.Substring($SchemaExtractPath.Length)
                    $destinationPath = Join-Path $targetDir $relativePath
                    if (Test-Path $_.FullName -PathType Leaf) {
                        Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                    }
                } else { Write-Host "跳过文件: $($_.Name)" -ForegroundColor Yellow }
            }
            Save-TimeRecord -filePath $TimeRecordFile -key $SchemaUpdateTimeKey -value $SchemaRemoteTime
            Remove-Item -Path $tempSchemaZip, $SchemaExtractPath -Recurse -Force
        }
    }

    if ($InputDictDown -eq "0") {
        # 下载词库
        $DictUpdateTimeKey = $KeyTable[$InputSchemaType] + "_dict_update_time"
        $DictUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $DictUpdateTimeKey
        $DictRemoteTime = [datetime]::Parse($ExpectedDictTypeInfo.updated_at)
        if (Compare-UpdateTime -localTime $DictUpdateTime -remoteTime $DictRemoteTime) {
            $UpdateFlag = $true
            Download-Files -assetInfo $ExpectedDictTypeInfo -outFilePath $tempDictZip
            Expand-ZipFile -zipFilePath $tempDictZip -destinationPath $DictExtractPath
          
            $sourceDir = Get-DictExtractedFolderPath -extractPath $DictExtractPath -assetName $KeyTable[$InputSchemaType]
            $dictTargetDir = Join-Path $targetDir $DictFileSaveDirTable[$DictFileSaveDirTableIndex]
            if (-not (Test-Path -Path $dictTargetDir)){ New-Item -ItemType Directory -Path $dictTargetDir | Out-Null }
          
            Stop-WeaselServer; Start-Sleep -Seconds 1
            Get-ChildItem -Path $sourceDir | ForEach-Object {
                if (-not (Test-SkipFile -filePath $_.Name)) {
                    Copy-Item -Path $_.FullName -Destination $dictTargetDir -Recurse -Force
                } else { Write-Host "跳过文件: $($_.Name)" -ForegroundColor Yellow }
            }
            Save-TimeRecord -filePath $TimeRecordFile -key $DictUpdateTimeKey -value $DictRemoteTime
            Remove-Item -Path $tempDictZip, $DictExtractPath -Recurse -Force
        }
    }

    function Update-GramModel {
        Download-Files -assetInfo $ExpectedGramTypeInfo -outFilePath $tempGram
        Stop-WeaselServer; Start-Sleep -Seconds 1
        Copy-Item -Path $tempGram -Destination $targetDir -Force
        $GramUpdateTimeKey = $GramReleaseTag + "_gram_update_time"
        $GramRemoteTime = [datetime]::Parse($ExpectedGramTypeInfo.updated_at)
        Save-TimeRecord -filePath $TimeRecordFile -key $GramUpdateTimeKey -value $GramRemoteTime
        Remove-Item -Path $tempGram -Force
        $UpdateFlag = $true
    }
  
    if ($InputGramModel -eq "0") {
        # 下载模型
        $GramUpdateTimeKey = $GramReleaseTag + "_gram_update_time"
        $GramUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $GramUpdateTimeKey
        $GramRemoteTime = [datetime]::Parse($ExpectedGramTypeInfo.updated_at)
        if (Compare-UpdateTime -localTime $GramUpdateTime -remoteTime $GramRemoteTime) {
            Update-GramModel
        }
    }
}

Write-Host "操作已完成！文件已部署到 Weasel 配置目录:$($targetDir)" -ForegroundColor Green

if ($UpdateFlag) {
    Start-WeaselServer
    # 等待1秒
    Start-Sleep -Seconds 1
    Write-Host "内容已更新，触发小狼毫重新部署..." -ForegroundColor Green
    Start-WeaselReDeploy
}

Exit-Tip 0
