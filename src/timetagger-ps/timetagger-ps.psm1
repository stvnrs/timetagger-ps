#Requires -Version 7.2
using module ./classes/activity.psm1
using module ./classes/timetagger.psm1

$ErrorActionPreference = 'Stop'
$script:TimeTaggerWrapper = [TimeTaggerWrapper]::new()
[ValidateSet('Pre', 'Post')]
$Script:TagPosition = 'Pre'

# get the date time truncated to seconds
function GetDate {
    $Now = Get-Date 
    $Now = $Now.AddTicks( - ($Now.Ticks % [timespan]::TicksPerSecond))
    $Now
}

function GetDescription {
    param(
        [string[]]$Tags,
        [string]$Description,
        [ValidateSet('Pre', 'Post')]
        [string]$TagPosition = 'Pre'
    )

    $Ret = $TagPosition -eq 'Pre' ? 
        ($Tags + $Description) -join ' ' :
        (, $Description + $Tags) -join ' '
       
    $Ret
}

function IsValidTag() {
    param (
        [String]$Tag
    )

    $Ret = $Tag -match '^#[a-z0-9][a-z0-9-]*[a-z0-9]$'

    return $Ret
}

function Add-Activity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ IsValidTag($_) })]
        [string[]]$Tags,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('From')]
        [datetime]$StartedAt,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('To')]
        [ValidateScript({ $EndedAt -gt $StartedAt })]
        [datetime]$EndedAt

    )

    $Description = GetDescription -Tags $Tags -Description $Description -TagPosition $Script:TagPosition
    $Activity = [Activity]::new($StartedAt, $EndedAt, $Description)
    
    Write-Verbose "Adding Activity: $Description"

    return $script:TimeTaggerWrapper.PutActivity($Activity)
}

function Get-Activity {
    [CmdletBinding(DefaultParameterSetName = 'ByDate')]
    param (
        [Parameter(ParameterSetName = 'ByDate')]
        [datetime]$From = (Get-Date).Date,

        [Parameter(ParameterSetName = 'ByDate')]
        [datetime]$To = (Get-Date).Date.AddDays(1),

        [Parameter(Mandatory = $true, ParameterSetName = "ByPeriod")]
        [ValidateSet('Today', 'Yesterday', 'ThisWeek', 'ThisMonth')]
        [string]$Period,

        [Parameter(ParameterSetName = "ByDate")]
        [Parameter(ParameterSetName = "ByPeriod")]
        [ValidateSet('Active', 'Stopped', 'All')]
        [string]$State = 'Active',

        [Parameter(ParameterSetName = "ByDate")]
        [Parameter(ParameterSetName = "ByPeriod")]
        [ValidateSet('Hidden', 'NotHidden', 'All')]
        [string]$Visibility = 'NotHidden'
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByPeriod') {
        $Today = (Get-Date).Date 

        switch ($Period) {
            'Today' { 
                $From = $Today
                $To = $From.AddDays(1)
            }
            'Yesterday' { 
                $From = $Today.AddDays(-1)
                $To = $From.AddDays(1)
            }
            'ThisWeek' {
                # monday is first day of week
                $From = $Today.AddDays( - ($Today.DayOfWeek - 1))
                $To = $Today.AddDays(1)
            }
            'ThisYear' {
                # from Jan 01           
                $From = [datetime]::new((Get-Date).Year, 1, 1)
                $To = $Today.AddDays(1)
            }
            Default {
                throw "Unknown Period"
            }
        }
    }

    $Activities = $script:TimeTaggerWrapper.GetActivities($From, $To)
    $Ret = @()

    foreach ($Activity in $Activities) {
        $Include = $true

        switch ($State) {
            'All' { $Include = $true }
            'Active' { $Include = $Activity.IsActive }
            'Stopped' { $Include = !$Activity.IsActive }
            Default {
                throw "Unexpected state in Get-Activity: $State"
            }
        }
        if ($Include) {
            switch ($Visibility) {
                'All' { $Include = $true }
                'Hidden' { $Include = $Activity.IsHidden }
                'NotHidden' { $Include = !$Activity.IsHidden }
                Default {
                    throw "Unexpected visibility in Get-Activity: $Visibility"
                }
            }
        }
        
        if ($Include) {
            $Ret += $Activity
        }
    }

    return $Ret
}


function Hide-Activity {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByActivity', ValueFromPipeline = $true, Position = 0)]
        [Activity]$Activity
    )
    
    begin {
        Write-Verbose "$($MyInvocation.MyCommand): begin"

        $outBuffer = $null
        
        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer)) {
            $PSBoundParameters['OutBuffer'] = 1
        }
        
        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand("$($MyInvocation.MyCommand.ModuleName)\Set-Activity", [System.Management.Automation.CommandTypes]::Function)
        $scriptCmd = { & $wrappedCmd @PSBoundParameters }

        $Pipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
        $Pipeline.Begin($PSCmdlet) 
    }
    
    process {
        $_.Hide()
        $Pipeline.Process($_)
    }
    
    end {
        Write-Verbose "$($MyInvocation.MyCommand): end"
    }
    
    clean {

    }
}

function Open-TimeTaggerApp {
    [CmdletBinding()]
    param (
    )

    Start-Process -FilePath 'https://timetagger.app/app/'
}

function Set-TimeTaggerAccount {
    param(
        [string]$ApiToken,
        [switch]$Persist
    )

    $Script:ApiToken = $ApiToken    

    $Password = ConvertTo-SecureString $ApiToken -AsPlainText -Force
    $Cred = New-Object "System.Management.Automation.PSCredential" ('<not-used>', $Password)
    
    $Cred | Export-Clixml -Path ~/.timetagger
}

function Set-Activity {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByActivity', ValueFromPipeline = $true, Position = 0)]
        [Activity]$Activity
    )

    begin {
        Write-Verbose 'Set-Activity: begin'
    }

    process {
        $script:TimeTaggerWrapper.PutActivity($_)
    }

    end {
        Write-Verbose 'Set-Activity: end'
    }

    clean {}
    
}

function Show-Activity {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByActivity', ValueFromPipeline = $true, Position = 0)]
        [Activity]$Activity
    )
    
    begin {
        Write-Verbose "$($MyInvocation.MyCommand): begin"

        $outBuffer = $null
        
        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer)) {
            $PSBoundParameters['OutBuffer'] = 1
        }
        
        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand("$($MyInvocation.MyCommand.ModuleName)\Set-Activity", [System.Management.Automation.CommandTypes]::Function)
        $scriptCmd = { & $wrappedCmd @PSBoundParameters }

        $Pipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
        $Pipeline.Begin($PSCmdlet) 
    }
    
    process {
        if ($_.IsHidden) {
            $_.Unhide()
            $Pipeline.Process($_)
        }
        else {
            Write-Warning "Activity (Key = $($Activity.Key) is not hidden)"
        }
    }
    
    end {
        Write-Verbose "$($MyInvocation.MyCommand): end"
        
    }
    
    clean {
        
    }
}

function Split-Activity {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByActivity', ValueFromPipeline = $true, Position = 0)]
        [Activity]$Activity,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByActivity', ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ $SplitFrom -gt $Activity.StartedAt })]
        [datetime]$SplitFrom,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByActivity', ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ $NewActivityStartedAt -ge $SplitFrom })]
        [datetime]$NewActivityStartedAt = $SplitFrom,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByActivity', ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ $NewActivityEndedAt -gt $NewActivityStartedAt })]
        [nullable[datetime]]$NewActivityEndedAt

    )

    $Activity.EndedAt = $SplitFrom
    Set-Activity -Activity $Activity

    $Params = @{
        Tags        = $Activity.Tags 
        Description = $Activity.Description
        StartedAt   = $NewActivityStartedAt
    }
        
    if ($null -eq $NewActivityEndedAt) {
        Start-Activity @Params 
    }
    else {
        Add-Activity @Params -EndedAt $NewActivityEndedAt
    }
}

function Start-Activity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ IsValidTag($_) })]
        [string[]]$Tags,

        [string]$Description,

        [Alias('From')]
        [datetime]$StartedAt = (Get-Date).ToUniversalTime(),

        [switch]$IgnoreRunning
    )

    if (!$IgnoreRunning.IsPresent) {
        Get-Activity -State 'Active' -From $StartedAt | Stop-Activity
    }

    $Description = GetDescription -Tags $Tags -Description $Description -TagPosition $Script:TagPosition
    $Activity = [Activity]::new($StartedAt, $Description)
    
    Write-Verbose "Starting Activity: $Description"

    return $script:TimeTaggerWrapper.PutActivity($Activity)
}

function Stop-Activity {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByActivity', ValueFromPipeline = $true, Position = 0)]
        [Activity]$Activity
    )

    begin {
        Write-Verbose 'Stop-Activity: begin'

        $outBuffer = $null
        
        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer)) {
            $PSBoundParameters['OutBuffer'] = 1
        }
        
        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand("$($MyInvocation.MyCommand.ModuleName)\Set-Activity", [System.Management.Automation.CommandTypes]::Function)
        $scriptCmd = { & $wrappedCmd @PSBoundParameters }

        $Pipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
        $Pipeline.Begin($PSCmdlet) 
    }

    process {
        $_.EndedAt = GetDate
        $Pipeline.Process($_)    
    }

    end {
        Write-Verbose 'Stop-Activity: end'
    }

    clean {}
    
}


