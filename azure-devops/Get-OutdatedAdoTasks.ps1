# ==============================================================================
# Get-OutdatedAdoTasks.ps1
#
# Scans all task groups in an Azure DevOps project and reports any tasks where
# the pinned major version is behind the latest available major version.
#
# USAGE:
#   .\Get-OutdatedAdoTasks.ps1 -OrgUrl <url> -Project <project> -Pat <pat>
#
# PARAMETERS:
#   -OrgUrl    Your ADO org URL. Example: https://dev.azure.com/myorg
#   -Project   The project to scan. Example: MyProject
#   -Pat       A Personal Access Token with Read access to Task Groups and Tasks
#
# OUTPUT:
#   Table of outdated tasks sorted by version gap (largest first).
#   Green message if everything is up to date.
#
# NOTES:
#   Run once per project. To cover multiple projects, run with different -Project values.
# ==============================================================================

param(
    [Parameter(Mandatory)] [string] $OrgUrl,
    [Parameter(Mandatory)] [string] $Project,
    [Parameter(Mandatory)] [string] $Pat
)

$token   = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
$headers = @{ Authorization = "Basic $token" }

$taskGroups     = (Invoke-RestMethod -Uri "$OrgUrl/$Project/_apis/distributedtask/taskgroups?api-version=7.1" -Headers $headers).value
$availableTasks = (Invoke-RestMethod -Uri "$OrgUrl/_apis/distributedtask/tasks?api-version=7.1" -Headers $headers).value

$latestVersionMap = @{}
foreach ($task in $availableTasks) {
    $id    = $task.id
    $major = $task.version.major
    if (-not $latestVersionMap.ContainsKey($id) -or $major -gt $latestVersionMap[$id].major) {
        $latestVersionMap[$id] = @{ major = $major; name = $task.name }
    }
}

$results = @()
foreach ($tg in $taskGroups) {
    foreach ($step in $tg.tasks) {
        $taskId    = $step.task.id
        $usedMajor = [int]($step.task.versionSpec -replace '\.\*', '' -replace '\*', '0')

        if ($latestVersionMap.ContainsKey($taskId)) {
            $latest = $latestVersionMap[$taskId]
            if ($usedMajor -lt $latest.major) {
                $results += [PSCustomObject]@{
                    TaskGroup   = $tg.name
                    Task        = $latest.name
                    UsedVersion = $step.task.versionSpec
                    LatestMajor = $latest.major
                    Gap         = $latest.major - $usedMajor
                }
            }
        }
    }
}

if ($results.Count -eq 0) {
    Write-Host "No outdated tasks found." -ForegroundColor Green
} else {
    $results | Sort-Object Gap -Descending | Format-Table -AutoSize
}
