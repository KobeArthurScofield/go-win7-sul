param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('ApplyPatch', 'CopyLicense', 'PromoteBinaries', 'CreateZip', 'ComputeHashes')]
    [string] $Action,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]] $Parameters
)

$ErrorActionPreference = 'Stop'

switch ($Action) {
    'ApplyPatch' {
        Push-Location go
        try {
            foreach ($patchFile in $Parameters) {
                patch --verbose -p 1 -i "..\patch\$patchFile"
                if ($LASTEXITCODE -ne 0) {
                    throw "Applying patch failed: $patchFile"
                }
            }
        }
        finally {
            Pop-Location
        }
    }

    'CopyLicense' {
        Copy-Item -LiteralPath patch/LICENSE -Destination go -Force
    }

    'PromoteBinaries' {
        Push-Location go/bin
        try {
            $targetDirectory = "${env:GOOS}_${env:GOARCH}"
            if (Test-Path -LiteralPath $targetDirectory -PathType Container) {
                Get-ChildItem -Path 'go*' | Remove-Item -Recurse -Force
                Get-ChildItem -LiteralPath $targetDirectory -Force | Move-Item -Destination .
                Remove-Item -LiteralPath $targetDirectory -Recurse -Force
                if (Test-Path -LiteralPath ../pkg/tool/linux_amd64) {
                    Remove-Item -LiteralPath ../pkg/tool/linux_amd64 -Recurse -Force
                }
            }
            Get-ChildItem -Force
        }
        finally {
            Pop-Location
        }
    }

    'CreateZip' {
        if ($Parameters.Count -ne 1) {
            throw 'CreateZip requires one archive filename.'
        }

        $root = (Resolve-Path go).Path
        $archivePath = Join-Path $root $Parameters[0]
        $files = Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object {
            $relativePath = [System.IO.Path]::GetRelativePath($root, $_.FullName)
            $parts = $relativePath -split '[\\/]'
            $isExcludedPath = @($parts | Where-Object { $_.StartsWith('.') -or $_ -eq 'testdata' }).Count -gt 0
            -not $isExcludedPath -and $_.Name -notlike '*_test.go'
        }

        $archiveStream = [System.IO.File]::Open($archivePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $archive = [System.IO.Compression.ZipArchive]::new($archiveStream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in $files) {
                $relativePath = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
                $entry = $archive.CreateEntry($relativePath, [System.IO.Compression.CompressionLevel]::Optimal)
                $entryStream = $entry.Open()
                $sourceStream = [System.IO.File]::OpenRead($file.FullName)
                try {
                    $sourceStream.CopyTo($entryStream)
                }
                finally {
                    $sourceStream.Dispose()
                    $entryStream.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
            $archiveStream.Dispose()
        }
    }

    'ComputeHashes' {
        if ($Parameters.Count -ne 1) {
            throw 'ComputeHashes requires one archive filename.'
        }

        $archivePath = Join-Path go $Parameters[0]
        $digestPath = "$archivePath.dgst"
        foreach ($algorithm in @('MD5', 'SHA1', 'SHA256', 'SHA512')) {
            $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm $algorithm).Hash
            Add-Content -LiteralPath $digestPath -Value "$algorithm = $hash"
        }
    }
}