[CmdletBinding()]
[OutputType([String])]
Param (
    [Parameter(Mandatory = $false)]
    [string] $Path = "$env:LocalAppData\Microsoft\Outlook"
)

#region Functions
Function ConvertFrom-Hex ($String) {
    $output = ($String.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) | `
            Where-Object { $_ -gt '0' } | ForEach-Object { [char][int]"$($_)" }) -join ''
    Write-Output $output
}

Function ConvertTo-Hex ($String) {
    $output = [System.Text.Encoding]::Unicode.GetBytes($String + "`0")
    Write-Output $output
    # Write-Output ($output -split ',')
}

Function Set-RegValue {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)] $Key,
        [Parameter(Mandatory = $True)] $Value,
        [Parameter(Mandatory = $True)] $Data,
        [Parameter(Mandatory = $False)]
        [ValidateSet('Binary', 'ExpandString', 'String', 'Dword', 'MultiString', 'QWord')]
        [string] $Type = "String"
    )
    try {
        If (!(Test-Path -Path $Key)) {
            New-Item -Path $Key -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Error "Failed to create key $Key with error $_."
        Break
    }
    finally {
        New-ItemProperty -Path $Key -Name $Value -Value $Data -PropertyType $Type -Force
    }
}
#endregion

# find key that has the 001f6700 property that holds the OST file path - one key per outlook profile.
$pstRegValue = '001f6700'
$keyPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles\"
$keys = @((Get-ChildItem $keyPath -Recurse | `
            Where-Object { $_.Property -eq $pstRegValue }).Name)

ForEach ($key in $keys) {
    $key = $key.Replace("HKEY_CURRENT_USER", "HKCU:")
    Write-Verbose -Message "Key: $key"

    # Grab the old path to the PST file
    $pstOldPathHex = (Get-ItemProperty -Path $key | Select-Object -ExpandProperty $pstRegValue) -join ','
    $pstOldPath = ConvertFrom-Hex $pstOldPathHex
    Write-Verbose -Message "Old PST path: $pstOldPath"

    # make sure it is an PST in this field
    If ($pstOldPath.SubString($pstOldPath.length - 4, 4) -eq ".pst") {

        $oldPstFileName = $pstOldPath.Split("\")
        $oldPstFileName = $oldPstFileName[$oldPstFileName.Count - 1]

        $newPstPath = Join-Path $TargetPath $oldPstFileName
        # $newPstPathHex = ConvertTo-Hex $newPstPath
        $newPstPathHex = [System.Text.Encoding]::Unicode.GetBytes($newPstPath + "`0")
        # $newPstPathHex = $newPstPathHex -join ','
        $newPstPathStr = ConvertFrom-Hex ($newPstPathHex -join ',')
        Write-Verbose -Message "New PST path: $newPstPathStr"

        # Set registry value with new PST file path
        If ($pscmdlet.ShouldProcess($newPstPathStr, "Set Registry")) {
            Set-RegValue -Key $key -Value $pstRegValue -Data $newPstPathHex -Type 'Binary'
        }
    }
}