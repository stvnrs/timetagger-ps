
using module ./activity.psm1

class TimeTaggerWrapper {
    [string] $TimeTaggerApiUri = 'https://timetagger.app/api/v2'

    hidden [object] InvokeEndPoint (
        [string]$EndPoint,
        [string]$Method,
        [hashtable]$QueryParams = @{},
        [hashtable]$Body = $null
    ) {
        $QueryString = ''
        $QueryParams.Keys | ForEach-Object {
            $QueryString += "$_=$($QueryParams[$_])"
        }
    
        Write-verbose "QueryString: $QueryString"
    
        $Uri = "$($this.TimeTaggerApiUri)/$EndPoint"
    
        if ($QueryString.Length -gt 0) {
            $Uri += "?$QueryString"
        }
    
        Write-verbose "Uri: $Uri"
        $Creds = Import-CliXml ~/.timetagger
        $ApiToken = $Creds.Password | ConvertFrom-SecureString -AsPlainText
        $Headers = @{authtoken = $ApiToken }
        $Params = @{
            Method  = $Method 
            Uri     = $Uri 
            Headers = $Headers 
        }
    
        if ($null -ne $Body) {
            $Params.Body = $Body | ConvertTo-Json -Compress -AsArray
            Write-Verbose "Body: $Params.Body"
        }
    
        $Response = Invoke-WebRequest @Params
    
        return $Response
    }
    
    [Activity[]] GetActivities ([datetime]$From, [datetime]$To) {

        $FromUnixEpoch = Get-Date $From -UFormat '%s'
        $ToUnixEpoch = Get-Date $To -UFormat '%s'
        $QueryParams = @{
            timerange = "$($FromUnixEpoch)-$ToUnixEpoch"
        }
    
        Write-Verbose "$($From.ToString('s')) ($FromUnixEpoch) -> $($To.ToString('s')) ($ToUnixEpoch)"

        $Response = $this.InvokeEndPoint('records', 'GET', $QueryParams, $null)
        $Ret = @()
        
        $Response.Content | ConvertFrom-Json | Select-Object -exp 'records' | ForEach-Object {
            $Activity = [Activity]::FromPSCustomObject($_)
            $Ret += $Activity
        }

        return $Ret
    }

    [void] PutActivity ([Activity]$Activity) {

        $Response = $this.InvokeEndPoint('records', 'PUT', @{}, $Activity.ToHashTable())

        $Status = $Response.Content | ConvertFrom-Json 

        if($Status.accepted -notcontains $Activity.Key){
            throw "failed to create activity: $($Activity.Serialize())"
        }
    }
}