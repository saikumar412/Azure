$environment = @("dev", "stg", "prod")
$alltags = foreach ($env in $environment) {
    # Get the list of images from k8s cluster
    $tags = az aks command invoke --resource-group test-shared-gw-$env --name test-aks-gw-$env --command "kubectl get pods --all-namespaces -o jsonpath='{.items[*].spec.containers[*].image}' | tr -s '[[:space:]]' '\n' | sort | uniq -c"
    # Skip the first line comments from PowerShell
    $deletefirstline = $tags | Select-Object -Skip 1
    # Remove the count of the images
    $removecount = $deletefirstline -replace '^\S*\s+'
    # Filter the image tags with "/cloud" in the name and extract the tags
    $removecount | Where-Object { $_ -like "*/cloud-*" } | ForEach-Object {
        # Extract the image name and version
        $nameVersion = $_ -split '[:/]'
        # Output the image name and version
        "$($nameVersion[2]), $($nameVersion[3])"
    }
}

$groupedData = $alltags | ForEach-Object {
    $parts = $_ -split ', '
    [PSCustomObject]@{ Key = $parts[0]; Value = $parts[1] }
} | Group-Object -Property Key

# Store the output in a variable
$sortedtags = $groupedData | ForEach-Object {
    $key = $_.Name
    $values = $_.Group | ForEach-Object { $_.Value }
    "$key = " + ($values -join "`n")
}

# Extract only the values for cloud-s1
$clouds1 = $sortedtags | Where-Object { $_ -like "cloud-s1*" } | ForEach-Object {
    $_ -replace "cloud-s1 = ", ""
}

# Extract only the values for cloud-s2
$clouds2 = $sortedtags | Where-Object { $_ -like "cloud-s2*" } | ForEach-Object {
    $_ -replace "cloud-s2 = ", ""
}

# Extract only the values for cloud-s3
$clouds3 = $sortedtags | Where-Object { $_ -like "cloud-s3*" } | ForEach-Object {
    $_ -replace "cloud-s3 = ", ""
}

# Extract only the values for cloud-s4
$clouds4 = $sortedtags | Where-Object { $_ -like "cloud-s4*" } | ForEach-Object {
    $_ -replace "cloud-s4 = ", ""
}

# Print the cloud-s1 values
$clouds1 = $clouds1 | ForEach-Object { "latest`n" + ($_ -replace '","', "`n" -replace '"', "") }
$clouds2 = $clouds2 | ForEach-Object { "latest`n" + ($_ -replace '","', "`n" -replace '"', "") }
$clouds3 = $clouds3 | ForEach-Object { "latest`n" + ($_ -replace '","', "`n" -replace '"', "") }
$clouds4 = $clouds4 | ForEach-Object { "latest`n" + ($_ -replace '","', "`n" -replace '"', "") }


$registryName = "testimggw"

# Define repositories and tags to exclude
$repositories = @{
    "org/cloud-s1" = $clouds1
    "org/cloud-s2" = $clouds2
    "org/cloud-s4" = $clouds4
    "org/cloud-s3" = $clouds3
}

foreach ($repository in $repositories.Keys) {
    $tagsToExclude = $repositories[$repository]

    Write-Output $tagsToExclude

    # List the tags in the repository
    $tagslist = az acr repository show-tags --name $registryName --repository $repository --output table

    # Skip the first line comments from PowerShell
    $tagslist = $tagslist | Select-Object -Skip 2

    # Convert $tagslist to an array of strings
    $tagsArray = $tagslist -split "`n"

    $tagsToExclude = $tagsToExclude -split '\r?\n'

    # Filter tags to exclude the specified ones
    $tagsToDelete = $tagsArray | Where-Object { $tagsToExclude -notcontains $_ }

    # Delete the remaining tags
    foreach ($tag in $tagsToDelete) {
        $imageToDelete = "$($repository):$($tag)"
        Write-Output $imageToDelete
        az acr repository delete --name $registryName --image $imageToDelete --yes 
    }
}

# Deleting manifests for images withtout images 
Foreach($x in (az acr repository show-manifests -n testimggw --repository org/cloud-s3 | ConvertFrom-Json)) { if (!$x.tags) { az acr repository delete -n testimggw --image "org/cloud-s3@$($x.digest)" -y }}

