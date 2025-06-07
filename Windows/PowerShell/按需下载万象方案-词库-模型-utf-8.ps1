############# 自动更新配置项，配置好后将 AutoUpdate 设置为 true 即可 #############
# $AutoUpdate = $true;
$AutoUpdate = $false;
####[0]-仓颉; [1]-小鹤; [2]-汉心; [3]-简单鹤; [4]-墨奇; [5]-虎码; [6]-五笔; [7]-自然码"
####注意必须包含双引号，例如：$InputSchemaType = "0";
$InputSchemaType = "7";
# $SkipFiles = @(
#     "wanxiang_en.dict.yaml",
#     "tone_fallback.lua",
#     "custom_phrase.txt"
# ); # 需要跳过的文件列表
############# 自动更新配置项，配置好后将 AutoUpdate 设置为 true 即可 #############

$UpdateToolsVersion = "DEFAULT_UPDATE_TOOLS_VERSION_TAG";
if ($UpdateToolsVersion.StartsWith("DEFAULT")) {
    Write-Host "您下载的是非发行版脚本，请勿直接使用，请去 releases 页面下载最新版本：https://github.com/expoli/rime-wanxiang-update-tools/releases" -ForegroundColor Yellow;
} else {
    Write-Host "当前更新工具版本：$UpdateToolsVersion" -ForegroundColor Yellow;
}

# 设置代理地址和端口，配置好后删除注释符号
# $proxyAddress = "http://127.0.0.1:7897"
# [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxyAddress)
# [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

# 设置仓库所有者和名称
$SchemaOwner = "amzxyz"
$SchemaRepo = "rime_wanxiang_pro"
$GramRepo = "RIME-LMDG"
$GramReleaseTag = "LTS"
$GramModelFileName = "wanxiang-lts-zh-hans.gram"
$ReleaseTimeRecordFile = "release_time_record.json"
# 定义临时文件路径
$tempSchemaZip = Join-Path $env:TEMP "wanxiang_schema_temp.zip"
$tempDictZip = Join-Path $env:TEMP "wanxiang_dict_temp.zip"
$tempGram = Join-Path $env:TEMP "wanxiang-lts-zh-hans.gram"
$tempGramMd5 = Join-Path $env:TEMP "wanxiang-lts-zh-hans.gram.md5"
$SchemaExtractPath = Join-Path $env:TEMP "wanxiang_schema_extract"
$DictExtractPath = Join-Path $env:TEMP "wanxiang_dict_extract"

$Debug = $false;

$KeyTable = @{
    "0" = "cj";
    "1" = "flypy";
    "2" = "hanxin";
    "3" = "jdh";
    "4" = "moqi";
    "5" = "tiger";
    "6" = "wubi";
    "7" = "zrm"
}

$GramKeyTable = @{
    "0" = "zh-hans.gram";
    "1" = "md5sum";
}

$GramFileTableIndex = 0;
$GramMd5TableIndex = 1;

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

function Get-ExtractedFolderPath {
    param(
        [string]$extractPath,
        [string]$assetName
    )
    $folders = Get-ChildItem -Path $extractPath -Directory
    foreach ($folder in $folders) {
        if ($folder.Name -match $assetName) {
            return $folder.FullName
        }
    }
    return Join-Path $extractPath $(Get-FileNameWithoutExtension -filePath $assetName)
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
        exit 1
    }
    Start-Process -FilePath (Join-Path $rimeInstallDir $rimeServerExecutable) -ArgumentList '/q'
}

function Start-WeaselServer {
    if (-not $rimeServerExecutable) {
        Write-Host "警告：未找到Weasel服务端可执行程序，请确保已正确安装小狼毫输入法" -ForegroundColor Yellow
        exit 1
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
    exit 1
}
Write-Host "Weasel用户目录路径为: $rimeUserDir"
$targetDir = $rimeUserDir
$TimeRecordFile = Join-Path $targetDir $ReleaseTimeRecordFile

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

    try {
        # 发送API请求
        $response = Invoke-RestMethod -Uri $apiUrl -Headers @{
            "User-Agent" = "PowerShell Release Downloader"
            "Accept" = "application/vnd.github.v3+json"
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        if ($statusCode -eq 404) {
            Write-Error "错误：仓库 '$owner/$repo' 不存在或没有发布版本"
        }
        else {
            Write-Error "API请求失败 [$statusCode]：$_"
        }
        exit 1
    }

    # 检查是否有可下载资源
    if ($response.assets.Count -eq 0) {
        Write-Error "该版本没有可下载资源" -ForegroundColor Red
        exit 1
    }
    return $response
}

# 获取最新的版本信息
$SchemaResponse = Get-ReleaseInfo -owner $SchemaOwner -repo $SchemaRepo
$GramResponse = Get-ReleaseInfo -owner $SchemaOwner -repo $GramRepo

$SelectedDictRelease = $null
$SelectedSchemaRelease = $null
$SelectedGramRelease = $null

foreach ($release in $SchemaResponse) {
    if (Test-DictSuffix -url $release.tag_name) {
        $SelectedDictRelease = $release
    }
    if (Test-VersionSuffix -url $release.tag_name) {
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
    exit 1
}

# 获取最新的版本的tag_name
Write-Host "最新的版本为：$($SelectedSchemaRelease.tag_name)"
$SchemaTag = $SelectedSchemaRelease.tag_name

$promptSchemaType = "请选择你要下载的辅助码方案类型的编号: `n[0]-仓颉; [1]-小鹤; [2]-汉心; [3]-简单鹤; [4]-墨奇; [5]-虎码; [6]-五笔; [7]-自然码"
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
            Write-Error "错误：方案号只能是0-7" -ForegroundColor Red
            exit 1
        }
        $InputAllUpdate = "0"
        $InputSchemaDown = "0"
        $InputGramModel = "0"
        $InputDictDown = "0"
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
        }
    }

    return $info
}

$ExpectedSchemaTypeInfo = Get-ExpectedAssetTypeInfo -index $InputSchemaType -keyTable $KeyTable -releaseObject $SelectedSchemaRelease
$ExpectedDictTypeInfo = Get-ExpectedAssetTypeInfo -index $InputSchemaType -keyTable $KeyTable -releaseObject $SelectedDictRelease
$ExpectedGramTypeInfo = Get-ExpectedAssetTypeInfo -index $GramFileTableIndex -keyTable $GramKeyTable -releaseObject $SelectedGramRelease
$ExpectedGramMd5TypeInfo = Get-ExpectedAssetTypeInfo -index $GramMd5TableIndex -keyTable $GramKeyTable -releaseObject $SelectedGramRelease

if (-not $ExpectedSchemaTypeInfo -or -not $ExpectedDictTypeInfo -or -not $ExpectedGramTypeInfo -or -not $ExpectedGramMd5TypeInfo) {
    Write-Error "未找到符合条件的下载链接" -ForegroundColor Red
    exit 1
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

    if ($localTime -eq $null) {
        Write-Host "本地时间记录不存在，将创建新的时间记录" -ForegroundColor Yellow
        return $true
    }

    $localTime = [datetime]::Parse($localTime)

    if ($remoteTime -eq $null) {
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
function Load-UpdateTimeKey {
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
$hasTimeRecord = Load-UpdateTimeKey -filePath $TimeRecordFile

if (-not $hasTimeRecord) {
    Write-Host "时间记录文件不存在，将创建新的时间记录" -ForegroundColor Yellow
}

# 创建目标目录（如果不存在）
if (-not (Test-Path $targetDir)) {
    Write-Host "创建目标目录: $targetDir" -ForegroundColor Green
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
}

# 下载函数
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
    }
    catch {
        Write-Host "下载失败: $_" -ForegroundColor Red
        exit 1
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
        Expand-Archive -Path $zipFilePath -DestinationPath $destinationPath -Force
        Write-Host "解压完成" -ForegroundColor Green
    }
    catch {
        Write-Host "解压失败: $_" -ForegroundColor Red
        Remove-Item -Path $zipFilePath -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

if ($InputSchemaDown -eq "0" -or $InputDictDown -eq "0" -or $InputGramModel -eq "0") {
    # 开始更新词库，从现在开始不要操作键盘，直到更新完成，否则会触发小狼毫重启，文件更新告警，导致更新失败，请放心更新完成后会自动拉起小狼毫
    Write-Host "正在更新词库，请不要操作键盘，直到更新完成" -ForegroundColor Red
    Write-Host "更新完成后会自动拉起小狼毫" -ForegroundColor Red
} else {
    Write-Host "没有指定要更新的内容，将退出" -ForegroundColor Red
    exit 0
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
        Write-Host "正在下载方案..." -ForegroundColor Green
        Download-Files -assetInfo $ExpectedSchemaTypeInfo -outFilePath $tempSchemaZip
        Write-Host "正在解压方案..." -ForegroundColor Green
        Expand-ZipFile -zipFilePath $tempSchemaZip -destinationPath $SchemaExtractPath
        Write-Host "正在复制文件..." -ForegroundColor Green
        $sourceDir = Get-ExtractedFolderPath -extractPath $SchemaExtractPath -assetName $KeyTable[$InputSchemaType]
        if (-not (Test-Path $sourceDir)) {
            Write-Host "错误：压缩包中未找到 $sourceDir 目录" -ForegroundColor Red
            Remove-Item -Path $tempSchemaZip -Force
            Remove-Item -Path $SchemaExtractPath -Recurse -Force
            exit 1
        }
        Stop-WeaselServer
        # 等待1秒
        Start-Sleep -Seconds 1
        Get-ChildItem -Path $sourceDir -Recurse | ForEach-Object {
            if ($_.Name -notin $SkipFiles) {
                $relativePath = $_.FullName.Substring($sourceDir.Length)
                $destinationPath = Join-Path $targetDir $relativePath
                $destinationDir = [System.IO.Path]::GetDirectoryName($destinationPath)
                if (-not (Test-Path $destinationDir)) {
                    New-Item -ItemType Directory -Path $destinationDir | Out-Null
                }
                if (Test-Path $_.FullName -PathType Container) {
                    if ($Debug) {
                        Write-Host "跳过目录: $($_.Name)" -ForegroundColor Yellow
                    }
                } elseif (Test-Path $_.FullName -PathType Leaf) {
                    Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                }

                if ($Debug) {
                    Write-Host "正在复制文件: $($_.Name)" -ForegroundColor Green
                    Write-Host "相对路径: $relativePath" -ForegroundColor Green
                    Write-Host "目标路径: $destinationPath" -ForegroundColor Green
                }
            } else {
                Write-Host "跳过文件: $($_.Name)" -ForegroundColor Yellow
            }
        }

        # 将现在的本地时间记录到JSON文件
        Save-TimeRecord -filePath $TimeRecordFile -key $SchemaUpdateTimeKey -value $SchemaRemoteTime
        # 清理临时文件
        Remove-Item -Path $tempSchemaZip -Force
        Remove-Item -Path $SchemaExtractPath -Recurse -Force
    }
}

if ($InputDictDown -eq "0") {
    # 下载词库
    $DictUpdateTimeKey = $KeyTable[$InputSchemaType] + "_dict_update_time"
    $DictUpdateTime = Get-TimeRecord -filePath $TimeRecordFile -key $DictUpdateTimeKey
    $DictRemoteTime = [datetime]::Parse($ExpectedDictTypeInfo.updated_at)
    Write-Host "正在检查词库是否需要更新..." -ForegroundColor Yellow
    Write-Host "本地时间: $DictUpdateTime" -ForegroundColor Green
    Write-Host "远程时间: $DictRemoteTime" -ForegroundColor Green
    if (Compare-UpdateTime -localTime $DictUpdateTime -remoteTime $DictRemoteTime) {
        $UpdateFlag = $true
        Write-Host "正在下载词库..." -ForegroundColor Green
        Download-Files -assetInfo $ExpectedDictTypeInfo -outFilePath $tempDictZip
        Write-Host "正在解压词库..." -ForegroundColor Green
        Expand-ZipFile -zipFilePath $tempDictZip -destinationPath $DictExtractPath
        Write-Host "正在复制文件..." -ForegroundColor Green
        $sourceDir = Get-ExtractedFolderPath -extractPath $DictExtractPath -assetName $KeyTable[$InputSchemaType]
        if (-not (Test-Path $sourceDir)) {
            Write-Host "错误：压缩包中未找到 $sourceDir 目录" -ForegroundColor Red
            Remove-Item -Path $DictExtractPath -Force -Recurse
            exit 1
        }
        Stop-WeaselServer
        # 等待1秒
        Start-Sleep -Seconds 1
        if (-not (Test-Path -Path $(Join-Path $targetDir "cn_dicts"))){
            New-Item -ItemType Directory -Path $(Join-Path $targetDir "cn_dicts") | Out-Null
        }
        Get-ChildItem -Path $sourceDir | ForEach-Object {
            if ($Debug) {
                Write-Host "正在复制文件: $($_.Name)" -ForegroundColor Green
            }
            if (Test-SkipFile -filePath $_.Name) {
                Write-Host "跳过文件: $($_.Name)" -ForegroundColor Yellow
            } else {
                Copy-Item -Path $_.FullName -Destination $(Join-Path $targetDir "cn_dicts") -Recurse -Force
            }
        }

        # 将现在的本地时间记录到JSON文件
        Save-TimeRecord -filePath $TimeRecordFile -key $DictUpdateTimeKey -value $DictRemoteTime -isDict $true
        # 清理临时文件
        Remove-Item -Path $DictExtractPath -Recurse -Force
    }
}

function Update-GramModel {
    $UpdateFlag = $true
    Write-Host "正在下载模型..." -ForegroundColor Green
    Download-Files -assetInfo $ExpectedGramTypeInfo -outFilePath $tempGram
    Write-Host "正在下载模型MD5..." -ForegroundColor Green
    Download-Files -assetInfo $ExpectedGramMd5TypeInfo -outFilePath $tempGramMd5
    Write-Host "正在验证模型MD5..." -ForegroundColor Green
    $remoteMd5 = (Get-Content -Raw $tempGramMd5).Split(' ')[0]
    $localMd5 = (Get-FileHash $tempGram -Algorithm MD5).Hash.ToLower()
    if ($remoteMd5 -ne $localMd5) {
        Write-Host "模型MD5验证失败" -ForegroundColor Red
        # Remove-Item -Path $tempGram -Force
        Remove-Item -Path $tempGramMd5 -Force
        exit 1
    }
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
    $GramRemoteTime = [datetime]::Parse($ExpectedGramTypeInfo.updated_at)
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
    }elseif (Test-Path -Path $filePath) {
        # 计算目标文件的MD5
        $localMd5 = (Get-FileHash $filePath -Algorithm MD5).Hash.ToLower()
        # 计算远程文件的MD5
        $remoteMd5 = (Get-Content -Raw $tempGramMd5).Split(' ')[0]
        # 比较MD5
        if ($localMd5 -ne $remoteMd5) {
            Write-Host "模型MD5不匹配，需要更新" -ForegroundColor Red
            Update-GramModel
        }   
    } else {
        Write-Host "模型不存在，需要更新" -ForegroundColor Red
        Update-GramModel
    }
}

Write-Host "操作已完成！文件已部署到 Weasel 配置目录:$($targetDir)" -ForegroundColor Green

if ($UpdateFlag) {
    Start-WeaselServer
    # 等待1秒
    Start-Sleep -Seconds 1
    Write-Host "内容更新，触发小狼毫重新部署..." -ForegroundColor Green
    Start-WeaselReDeploy
}
