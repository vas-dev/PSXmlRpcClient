function Invoke-XmlRpcRequest {
    <#
    .SYNOPSIS
    发送XML-RPC请求
    .DESCRIPTION
    发送XML-RPC请求，如果服务器响应为200，则解析服务器响应；否则输出异常信息
    .PARAMETER ServerUri
    XML-RPC服务器地址
    .PARAMETER MethodName
    要调用的方法名称
    .PARAMETER Params
    要传递给方法的参数，可以为空
    .INPUTS
    uri
    string
    array
    .OUTPUTS
    object
    .EXAMPLE
    Invoke-XmlRpcRequest -Url "example.com" -MethodName "system.methodHelp" -Params "phone"
    ---------
    Description
    Calls a method "system.methodHelp("phone")" on the server example.com
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory=$true)]
        [uri]$ServerUri,

        [Parameter(Mandatory=$true)]
        [string]$MethodName,

        [array]$Params
    )

    $body=$(ConvertTo-XmlRpcPayload -MethodName $MethodName -Params $Params)

    # ================================
    # works well
    $webRequest=[System.Net.HttpWebRequest]::CreateHttp($ServerUri)
    $webRequest.ServicePoint.Expect100Continue=$false
    $webRequest.AllowAutoRedirect=$true
    $webRequest.KeepAlive=$false
    $webRequest.ProtocolVersion=[System.Net.HttpVersion]::Version11
    $webRequest.Method="POST"

    $bytes=[System.Text.Encoding]::UTF8.GetBytes($body)
    $req=$webRequest.GetRequestStream()
    $req.Write($bytes, 0, $bytes.Length)
    $req.Dispose()

    $resp=[System.Net.HttpWebResponse]$webRequest.GetResponse()
    $stream=$resp.GetResponseStream()
    $sr=New-Object System.IO.StreamReader($stream)
    $response=$sr.ReadToEnd()
    $sr.Dispose()
    $stream.Dispose()
    $resp.Dispose()
    # ================================

    # 使用“2”个参数调用“UploadString”时发生异常:“服务器提交了协议冲突. Section=ResponseStatusLine”
    # 有个比较奇怪的现象：
    # 1、连续两次请求的第二次必出现该问题
    # 2、与两次请求的先后顺序无关
    # 3、连续四次请求的第二次、第四次必出现该问题
    # $tmp=[System.Net.ServicePointManager]::Expect100Continue
    # [System.Net.ServicePointManager]::Expect100Continue = $false
    # $client = New-Object System.Net.WebClient
    # try {
    #     $client.Encoding = [System.Text.Encoding]::UTF8
    #     $response = $client.UploadString($ServerUri, $body)
    # }
    # finally {
    #     [System.Net.ServicePointManager]::Expect100Continue=$tmp
    #     $client.Dispose()
    # }

    # Invoke-RestMethod :    417 - Expectation Failed
    # $request=@{uri=$ServerUri;
    #         Method="POST";
    #         Headers=@{Authorization="Basic <base64-encoded-credentials>"; "Content-Type"="text/xml"}
    #         Body=$body}
    # $response=$(Invoke-RestMethod -UseBasicParsing @request -DisableKeepAlive)

    # Invoke-RestMethod :    417 - Expectation Failed
    # $response=$(Invoke-RestMethod -Uri $ServerUri -UseBasicParsing -Method "POST" -Body $body)

    # Invoke-WebRequest :    417 - Expectation Failed
    # $response=$(Invoke-WebRequest -UseBasicParsing -Uri $ServerUri -DisableKeepAlive -Method "POST" -Body $body -ContentType "text/xml")

    if ($response) {
        ConvertFrom-Xml -Xml $response
    }
}

function ConvertTo-XmlRpcPayload {
    <#
    .SYNOPSIS
    将方法名和参数转换为XML-RPC格式的xml
    .DESCRIPTION
    将方法名和参数转换为XML-RPC格式的xml
    .PARAMETER MethodName
    要调用的方法名称
    .PARAMETER Params
    要传递给方法的参数，可以为空
    .INPUTS
    string
    array
    .OUTPUTS
    string
    .EXAMPLE
    ConvertTo-XmlRpcPayload -MethodName "system.methodHelp" -Params "phone"
    ---------
    Description
    Convert method "system.methodHelp("phone")" to XML in XML-RPC request
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory=$true)]
        [string]$MethodName,

        [array]$Params
    )

    $requestXml="<?xml version='1.0'?><methodCall><methodName>{0}</methodName><params>{1}</params></methodCall>"

    $paramsBuilder=[System.Text.StringBuilder]::new()
    $Params | ForEach-Object {
        if ($_) {
            [void]$paramsBuilder.AppendFormat("<param><value>{0}</value></param>", $(ConvertTo-XmlRpcType -InputObject $_))
        }
    }

    return $([xml]($requestXml -f $MethodName, $paramsBuilder.ToString())).OuterXml
}

function ConvertTo-XmlRpcType {
    <#
    .SYNOPSIS
    将PowerShell类型转换为XML-RPC格式的xml
    .DESCRIPTION
    将PowerShell类型转换为XML-RPC格式的xml
    .PARAMETER InputObject
    PowerShell类型
    .INPUTS
    object
    .OUTPUTS
    string
    .EXAMPLE
    ConvertTo-XmlRpcType -InputObject 365
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        $InputObject
    )

    begin {
        # 在模块清单（psd1）文件中添加依赖在脚本中不好使？？？
        # RequiredAssemblies = @("System.Web.dll")
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Web")
    }

    process {
        # four-byte signed integer
        if ($InputObject -is [int]) {
            # return "<i4>$InputObject</i4>"
            return "<int>$InputObject</int>"
        }
        # 0 (false) or 1 (true)
        if ($InputObject -is [bool]) {
            if ($InputObject) { $boolValue=1 } else { $boolValue=0 }
            return "<boolean>$boolValue</boolean>"
        }
        # string
        if ($InputObject -is [string]) {
            return "<string>$([System.Web.HttpUtility]::HtmlEncode($InputObject))</string>"
            # return "<string>$InputObject</string>"
        }
        # double-precision signed floating point number
        if (($InputObject -is [double]) -or ($InputObject -is [float]) -or ($InputObject -is [decimal])) {
            return "<double>$InputObject</double>"
        }
        # date/time
        if ($InputObject -is [datetime]) {
            return "<dateTime.iso8601>$($InputObject.ToString('yyyyMMddTHH:mm:ss'))</dateTime.iso8601>"
        }
        # base64-encoded binary
        if (($InputObject -is [array]) -and ($InputObject.Length -gt 0) -and ($InputObject[0] -is [byte])) {
            return "<base64>$([System.Convert]::ToBase64String($InputObject))</base64>"
        }
        # <struct>s
        if ($InputObject -is [hashtable]) {
            $structBuilder=[System.Text.StringBuilder]::new()
            [void]$structBuilder.Append("<struct>")
            $InputObject.Keys | ForEach-Object {
                [void]$structBuilder.AppendFormat("<member><name>{0}</name><value>{1}</value></member>", $_, $(ConvertTo-XmlRpcType -InputObject $InputObject[$_]))
            }
            [void]$structBuilder.Append("</struct>")
            return $structBuilder.ToString()
        }
        # <array>s
        if ($InputObject -is [array]) {
            $arrayBuilder=[System.Text.StringBuilder]::new()
            [void]$arrayBuilder.Append("<array><data>")
            foreach ($obj in $InputObject) {
                [void]$arrayBuilder.AppendFormat("<value>{0}</value>", $(ConvertTo-XmlRpcType -InputObject $obj))
            }
            [void]$arrayBuilder.Append("</data></array>")
            return $arrayBuilder.ToString()
        }
        throw "$($InputObject.GetType().Name) type is not supported."
    }

    end {

    }
}

function ConvertFrom-Xml {
    <#
    .SYNOPSIS
    将XML-RPC服务器响应的xml转换为PowerShell类型
    .DESCRIPTION
    将XML-RPC服务器响应的xml转换为PowerShell类型
    .PARAMETER Xml
    XML-RPC格式的xml
    .INPUTS
    string or xml
    .OUTPUTS
    object
    .EXAMPLE
    ConvertFrom-Xml -Xml "<?xml version='1.0'?><methodResponse><params><param><value><string>South Dakota</string></value></param></params></methodResponse>"
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory=$true)]
        $Xml
    )

    if ($Xml -is [string]) {
        $XmlDocument=[xml]$Xml
    } elseif ($Xml -is [xml]) {
        $XmlDocument=$Xml
    }

    if ($XmlDocument -isnot [System.Xml.XmlDocument]) {
        throw "Only types [string](xml format), [xml] are supported"
    }

    # normal response
    foreach ($param in $XmlDocument.methodResponse.params.param) {
        foreach ($value in $param.value) {
            ConvertFrom-XmlRpcType -XmlObject $value.FirstChild
        }
    }

    # fault response
    foreach ($fault in $XmlDocument.methodResponse.fault) {
        foreach ($value in $fault.value) {
            ConvertFrom-XmlRpcType -XmlObject $value.struct
        }
    }
}

function ConvertFrom-XmlRpcType {
    <#
    .SYNOPSIS
    将XML-RPC格式的xml转换为PowerShell类型
    .DESCRIPTION
    将XML-RPC格式的xml转换为PowerShell类型
    .PARAMETER XmlObject
    XML-RPC格式的xml
    .INPUTS
    string or xml
    .OUTPUTS
    int
    bool
    double
    datetime
    byte[]
    hashtable
    .EXAMPLE
    ConvertFrom-XmlRpcType -XmlObject "<string>South Dakota</string>"
    #>
    [CmdletBinding()]
    [OutputType([int])]
    [OutputType([bool])]
    [OutputType([double])]
    [OutputType([datetime])]
    [OutputType([byte[]])]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory=$true)]
        $XmlObject
    )

    if ($XmlObject -is [string]) {
        $XmlObject=$([xml]$XmlObject).DocumentElement
    } elseif ($XmlObject -is [xml]) {
        $XmlObject=$XmlObject.DocumentElement
    }

    if ($XmlObject -isnot [System.Xml.XmlElement]) {
        throw "Only types [string](xml format), [xml], [System.Xml.XmlElement] are supported"
    }

    switch ($XmlObject.Name) {
        # four-byte signed integer
        "i4" {
            [int]::Parse($XmlObject.InnerText)
            break
        }
        "int" {
            [int]::Parse($XmlObject.InnerText)
            break
        }
        # 0 (false) or 1 (true)
        "boolean" {
            if ($XmlObject.InnerText -eq "1") {return $true} else {return $false}
            break
        }
        # string
        "string" {
            $XmlObject.InnerText
            break
        }
        # double-precision signed floating point number
        "double" {
            [double]::Parse($XmlObject.InnerText)
            break
        }
        # date/time
        "dateTime.iso8601" {
            [datetime]::ParseExact($XmlObject.InnerText, "yyyyMMddTHH:mm:ss", [cultureinfo]::InvariantCulture)
            break
        }
        # base64-encoded binary
        "base64" {
            [System.Convert]::FromBase64String($XmlObject.InnerText)
            break
        }
        # <struct>s
        "struct" {
            $hashTable=@{}
            $XmlObject.SelectNodes("member") | ForEach-Object {
                $hashTable[$_.name] = $(ConvertFrom-XmlRpcType -XmlObject $_.value.FirstChild)
            }
            return $hashTable
            break
        }
        # <array>s
        "array" {
            $XmlObject.SelectNodes("data/value") | ForEach-Object {
                ConvertFrom-XmlRpcType -XmlObject $_.FirstChild
            }
            break
        }
    }
}