GetADORepoSizes is a powershell script that aims to get 'approximate' sizes of repositories from ADO service and servers.
This is useful information when trying to scope out migrations from TFVC to git.

Instructions:

Create an ADO Personal Access Token we will use in the script.  Create with “full access” as we will delete later. Please be sure to save the PAT (string of text) as you cannot get it again and will need to create a new one if you do not.
https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=tfs-2017&tabs=preview-page#create-personal-access-tokens-to-authenticate-access

Download the powershell file from this repo.
Open a PowerShell command window
Run the following command (insert your ADO Org URL and the PAT created above)
.\Get-ADORepoSizes.ps1 -CollectionUrl https://YourUrl -PersonalAccessToken yourpat

 

Example: .\Get-ADORepoSizes.ps1 -CollectionUrl https://dev.azure.com/AaronKowall -PersonalAccessToken aqnnj7ddt4vax34mzgzwgdkxv7de7xd5djeeflzvibieja5liyaa

That ‘should’ create a file in the same directory as the .ps1 file named “ADORepos-youcollection-.csv”

Then remember to delte the PAT created earlier.
