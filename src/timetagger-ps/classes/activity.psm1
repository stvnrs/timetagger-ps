
class Activity {
    [string] $Key    
    [datetime] $StartedAt
    [Nullable[datetime]] $EndedAt
    [string] $Description
    [Nullable[datetime]] $ModifiedAt
    [Nullable[datetime]] $SystemTime
    hidden static [string] $ValidTagExpr = '#[a-z0-9][a-z0-9-]*[a-z0-9]'
    hidden static [string] $HiddenPrefix = 'HIDDEN'

    hidden static [void] Init(){
        [hashtable[]] $MemberDefinitions = @(
            @{
                MemberType = 'ScriptProperty'
                MemberName = 'IsActive'
                Value = { $this.StartedAt -eq $this.EndedAt }
            }
            @{
                MemberType = 'ScriptProperty'
                MemberName = 'IsHidden'
                Value = { $this.Description.StartsWith([Activity]::HiddenPrefix) }
            }
        )

        $TypeName = [Activity].Name
        foreach ($Definition in $MemberDefinitions) {
            Update-TypeData -TypeName $TypeName @Definition
        }
    }

    Activity() {
    }
    
    Activity([datetime]$StartedAt, [string]$Description) {
        $this.Key = New-NanoId -Size 8
        $this.StartedAt = $StartedAt
        $this.EndedAt = $StartedAt
        $this.Description = $Description
    }

    Activity([datetime]$StartedAt, [datetime]$EndedAt, [string]$Description) {
        $this.Key = New-NanoId -Size 8
        $this.StartedAt = $StartedAt
        $this.EndedAt = $EndedAt
        $this.Description = $Description
    }

    [string[]] GetTags() {
        $Ret = @()
        
        $this.Description |  Select-String -Pattern $this.ValidTagExpr -AllMatches | % {
            $Ret += $_.Matches.Value
        }

        return $Ret
    }
    
    [int] GetUnixEpochTime([datetime] $Date) {
        $Ret = Get-Date $Date -UFormat '%s'
        return $Ret
    }

    static [Activity] Deserialize([string]$SerialisedActivity) {
        $Values = $SerialisedActivity | ConvertFrom-Json -AsHashtable
        return [Activity]::FromHashTable($Values)
    }

    [void] Hide() {
        if (!$this.IsHidden) {
            $this.Description = "$([Activity]::HiddenPrefix) $($this.Description)"
        }
    }

    static [Activity] FromHashTable([hashtable]$Values) {
        $Ret = [Activity]::new()
        $Ret.Key = $Values.key
        $Ret.StartedAt = Get-Date -UnixTimeSeconds $Values.t1
        $Ret.EndedAt = Get-Date -UnixTimeSeconds $Values.t2
        $Ret.Description = $Values.ds
        $Ret.ModifiedAt = Get-Date -UnixTimeSeconds $Values.mt
        $Ret.SystemTime = Get-Date -UnixTimeSeconds $Values.st
        
        return $Ret
    }

    static [Activity] FromPSCustomObject([pscustomobject]$Object) {
        $Ret = [Activity]::new()
        $Ret.Key = $Object.key
        $Ret.StartedAt = Get-Date -UnixTimeSeconds $Object.t1
        $Ret.EndedAt = Get-Date -UnixTimeSeconds $Object.t2
        $Ret.Description = $Object.ds
        $Ret.ModifiedAt = Get-Date -UnixTimeSeconds $Object.mt
        $Ret.SystemTime = Get-Date -UnixTimeSeconds $Object.st
        
        return $Ret
    }

    [string] Serialize() {
        $Ret = $this.ToHashTable()
        return ($Ret | ConvertTo-Json -Compress -AsArray)
    }   

    [hashtable]ToHashTable() {
        $Ret = [ordered]@{
            key = $this.Key
            t1  = $this.GetUnixEpochTime($this.StartedAt)
            t2  = $this.GetUnixEpochTime($this.EndedAt ?? $this.StartedAt)
            ds  = $this.Description
            mt  = $this.GetUnixEpochTime($this.ModifiedAt ?? (Get-Date))
            st  = $this.GetUnixEpochTime($this.SystemTime ?? (Get-Date -UnixTimeSeconds 0))
        }

        return $Ret 
    }
    
    [void] Unhide() {
        if ($this.IsHidden) {
            $this.Description = $this.Description.Substring([Activity]::HiddenPrefix.Length).Trim()
        }
    }

}

[Activity]::Init()