Param 
(
    [string]$CollectionUrl,
    [string]$ProjectName,
    [string]$PersonalAccessToken
)

function Invoke-RestCommand {
    param(
        [string]$uri,
        [string]$commandType,
        [string]$contentType = "application/json",
        [string]$jsonBody,
        [string]$personalAccessToken
    )
	
    if ($null -ne $jsonBody) {
        $jsonBody = $jsonBody.Replace("{{", "{").Replace("}}", "}")
    }

    Write-Debug "REST CALL Url $uri"

    try {
        if ([String]::IsNullOrEmpty($personalAccessToken)) {
            if ([String]::IsNullOrEmpty($jsonBody)) {
                $response = Invoke-RestMethod -Method $commandType -ContentType $contentType -Uri $uri -UseDefaultCredentials
            }
            else {
                $response = Invoke-RestMethod -Method $commandType -ContentType $contentType -Uri $uri -UseDefaultCredentials -Body $jsonBody
            }
        }
        else {
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "", $personalAccessToken)))
            if ([String]::IsNullOrEmpty($jsonBody)) {            
                $response = Invoke-RestMethod -Method $commandType -ContentType $contentType -Uri $uri -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
            }
            else {
                $response = Invoke-RestMethod -Method $commandType -ContentType $contentType -Uri $uri -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $jsonBody
            }
        }

        if ($response.count) {
            $response = $response.value
        }

        foreach ($r in $response) {
            if ($r.code -eq "400" -or $r.code -eq "403" -or $r.code -eq "404" -or $r.code -eq "409" -or $r.code -eq "500") {
                Write-Error $_
                Write-Error -Message "Problem occurred when trying to call rest method."
                ConvertFrom-Json $r.body | Format-List
            }
        }

        return $response
    }
    catch {
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Error $responseBody
        Write-Error $_
        Write-Error -Message "Exception thrown calling REST method."
    }
}

function Get-Projects {
    param
    (
        [string]$collectionUrl,
        #[string]$projectName,
        [string]$personalAccessToken
    )

    $uri = "$($collectionUrl)/_apis/projects?api-version=3.0"

    $projects = Invoke-RestCommand -uri $uri -commandType "GET" -personalAccessToken $personalAccessToken

    return $projects
}

function Get-GitRepos {
    param
    (
        [string]$collectionUrl,
        [string]$projectName,
        [string]$personalAccessToken
    )

    $uri = "$($collectionUrl)/$($projectName)/_apis/git/repositories?api-version=5.1"

    $repos = Invoke-RestCommand -uri $uri -commandType "GET" -personalAccessToken $personalAccessToken

    return $repos
}

function Get-TFVCRepoSize {
    param
    (
        [string]$collectionUrl,
        [string]$projectName,
        [string]$personalAccessToken
    )

    # This API doesn't returned deleted items
    # Recursion level full may be too much into large repos and perhaps we should done one level and then recurse on folders

    $uri = "$($collectionUrl)/_apis/tfvc/items?scopePath=$/&recursionLevel=Full&api-version=5.1"

    # TO get values by project change to
    $encodedProjectName = [System.Web.HTTPUtility]::UrlEncode($projectName)
    $uri = "$($collectionUrl)/_apis/tfvc/items?scopePath=$/$($encodedProjectName)&recursionLevel=Full&api-version=5.1"


    $items = Invoke-RestCommand -uri $uri -commandType "GET" -personalAccessToken $personalAccessToken
    $repoSize = 0
    $binarySize = 0

    $binaryRevisions = 0
    $binaryFiles = 0

    foreach ($item in $items) {
        Write-Debug "Binary= $item"

        # A binary file is a file > 16MB that doesn't uses diffing. 
        if (($item.IsFolder -ne $true) -and ($item.encoding -eq -1)) {
            $binaryFiles++

            $changesets = Get-TFVCItemChangesets -collectionUrl $collectionUrl -personalAccessToken $personalAccessToken -path $item.path -fileName
            foreach ($changeset in $changesets) {
                # The fact the file participated in changeset doesn't mean it's size has changed. (eg: deletion), but its a fair approximantion
                $itemSize = Get-TFVCItemSize -collectionUrl $collectionUrl -personalAccessToken $personalAccessToken -path $item.path -fileName $item.fileName -version $changeset.changesetId
                $binarySize = $binarySize + $itemSize
                $binaryRevisions++;

            }
            $repoSize = $repoSize + $item.size

        }
        else {
            #text file
            $repoSize = $repoSize + $item.size
        }
    }

    Write-Host "   TFVC repoSize=$repoSize binarySize=$binarySize binaryFiles=$binaryFiles binaryRevisions=$binaryRevisions"

    return $repoSize, $binarySize, $binaryFiles, $binaryRevisions
}

function Get-TFVCItemChangesets {
    param
    (
        [string]$collectionUrl,
        [string]$personalAccessToken,
        [string]$path
        #   [string]$fileName,
        #   [string]$version
    )

    $encodedPath = [System.Web.HTTPUtility]::UrlEncode($path)

    $uri = "$($collectionUrl)/_apis/tfvc/changesets?searchCriteria.itemPath=$($encodedPath)&recursionLevel=none&api-version=5.1"

    $changesets = Invoke-RestCommand -uri $uri -commandType "GET" -personalAccessToken $personalAccessToken

    return $changesets
}

function Get-TFVCItemsize {
    param
    (
        [string]$collectionUrl,
        [string]$personalAccessToken,
        [string]$path,
        #   [string]$fileName,
        [string]$version
    )

    # Ideally we would call this https://docs.microsoft.com/en-us/rest/api/azure/devops/tfvc/items/get?view=azure-devops-rest-5.1#tfvcitem API with HEAD just to get the size
    # Alas HEAD is not supported :(

    $encodedPath = [System.Web.HTTPUtility]::UrlEncode($path)

    $uri = "$($collectionUrl)/_apis/tfvc/items?scopePath=$($encodedPath)&versionDescriptor.version=$($version)&versionDescriptor.versionType=changeset&api-version=5.1"

    $item = Invoke-RestCommand -uri $uri -commandType "GET" -personalAccessToken $personalAccessToken

    return $item.size
}

# $CollectionUrl = 

# $PersonalAccessToken = 

$CollectionUrl = $CollectionUrl.TrimEnd("/")

$organizationName = $CollectionUrl.Substring($CollectionUrl.LastIndexOf("/") + 1)

$reposList = New-Object System.Collections.ArrayList($null)

$projects = Get-Projects -collectionUrl $CollectionUrl -personalAccessToken $PersonalAccessToken

foreach ($project in $projects) {
    $projectName = $Project.Name

    Write-Output "Project $projectName"

    $repos = Get-GitRepos -collectionUrl $CollectionUrl -projectName $projectName -personalAccessToken $PersonalAccessToken

    foreach ($repo in $repos) {    

        Write-Output "   Repo $($repo.Name)"
     
        $reposList.Add([PSCustomObject]@{
                Project              = $($project.Name)
                Repo                 = $($repo.Name)
                RepoSize             = $($repo.size)
                Uri                  = $($repo.RemoteUrl)
                BinaryFiles          = ""
                BinaryFilesRevisions = ""
            }) | Out-Null
    } 
    
    Write-Output "   TFCV"

    $repoSizes = Get-TFVCRepoSize -collectionUrl $CollectionUrl -projectName $projectName -personalAccessToken $PersonalAccessToken
    
    if ($null -ne $repoSizes) {

        $reposList.Add([PSCustomObject]@{
                Project              = "$projectName TFVC"
                Repo                 = "$/projectName"
                RepoSize             = $($repoSizes[0])
                BinaryFiles          = ""
                BinaryFilesRevisions = ""
            }) | Out-Null

        $reposList.Add([PSCustomObject]@{
                Project              = "$projectName TFVCBinaries"
                Repo                 = "$/projectName"
                RepoSize             = $($repoSizes[1])
                BinaryFiles          = $($repoSizes[2])
                BinaryFilesRevisions = $($repoSizes[3])
            }) | Out-Null
    }

}


$reposList | Export-Csv ADORepos-$($organizationName).csv -NoTypeInformation