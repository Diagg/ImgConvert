$NewImage = "C:\Users\Diagg\OneDrive\Images\abstract\RollerCoaster_by_bdk14.jpg"
Foreach ($item in (Get-ChildItem "$env:ProgramData\Microsoft\User Account Pictures\*" -Include *.png))
	{
		If (($SubItem = ($item.basename).split("-")).count -gt 1){$Scale = [int]$SubItem[1]}Else{$Scale = 448}
		Remove-item $($item.DirectoryName + "\" + $item.Name + ".bak") -ErrorAction SilentlyContinue
		Rename-Item -Path $item.fullName  -NewName  $($item.Name + ".bak")
		$Newpath = $($item.DirectoryName + "\" + $item.BaseName + "." + $NewImage.Split(".")[1])
		Copy-Item -Path $NewImage -Destination $Newpath
		& "$(split-path $MyInvocation.MyCommand.Path)\ImgConvert.ps1" -files $Newpath -png -ScaleXto $Scale -ScaleYto $Scale
		Remove-Item $Newpath
	}