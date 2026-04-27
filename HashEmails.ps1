[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)] [string]$InputFile,
    [Parameter(Mandatory=$true)] [string]$OutputFile,
    [Parameter(Mandatory=$true)] [string]$SaltKey,
    [Parameter(Mandatory=$false)] [string]$Delimiter = ";" 
)

process {
    $fullInputPath = if ([System.IO.Path]::IsPathRooted($InputFile)) { $InputFile } else { Join-Path $PSScriptRoot $InputFile }
    $fullOutputPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path $PSScriptRoot $OutputFile }

    if (Test-Path $fullInputPath) {
        Write-Host "Cleaning and Loading CSV..." -ForegroundColor Cyan
        
        # 1. PRE-FILTER: Read raw lines and only keep those containing the delimiter
        # This skips empty lines or lines that would break the CSV structure.
        $rawContent = Get-Content $fullInputPath
        $filteredContent = $rawContent | Where-Object { $_ -like "*$Delimiter*" }
        
        if ($filteredContent.Count -lt 2) {
            Write-Error "No valid data rows found with delimiter '$Delimiter'."
            return
        }

        # 2. CONVERT: Turn the filtered text into CSV objects
        $data = $filteredContent | ConvertFrom-Csv -Delimiter $Delimiter
        $totalRows = $data.Count
        $currentRow = 0
        
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $utf8 = [System.Text.Encoding]::UTF8
        $emailRegex = "(?i)^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"

        Write-Host "Anonymizing $totalRows valid rows..." -ForegroundColor Cyan

        # 3. PROCESS
        foreach ($row in $data) {
            $currentRow++
            if ($currentRow % 100 -eq 0 -or $currentRow -eq $totalRows) {
                Write-Progress -Activity "Hashing Emails" -Status "Row $currentRow of $totalRows" -PercentComplete (($currentRow/$totalRows)*100)
            }

            foreach ($property in $row.PSObject.Properties) {
                $val = $property.Value
                if ($null -ne $val -and $val.Trim() -match $emailRegex) {
                    $normalized = $val.Trim().ToLower()
                    $combined = $normalized + $SaltKey
                    $hashBytes = $md5.ComputeHash($utf8.GetBytes($combined))
                    $property.Value = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
                }
            }
        }

        # 4. EXPORT
        Write-Host "Exporting to: $fullOutputPath" -ForegroundColor Gray
        $data | Export-Csv -Path $fullOutputPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

        $md5.Dispose()
        Write-Host "`nSuccess! Processed $totalRows rows (skipped lines without '$Delimiter')." -ForegroundColor Green
    } else {
        Write-Error "File not found: $fullInputPath"
    }
}