#Function ImgConvert
#	{
		# ImgConvert - Converts RAW (and other) image files to the widely-supported JPEG or PNG formats
		# 
		# Most of the awesome work by David Anson from MSFT(https://dlaa.me/blog/post/converttojpeg).
		# https://github.com/DavidAnson/ConvertTo-Jpeg
		#
		# PNG support and scaling by Diagg from www.OSD-couture.com

		Param (
		    [Parameter(
		        Mandatory = $true,
		        Position = 1,
		        ValueFromPipeline = $true,
		        ValueFromPipelineByPropertyName = $true,
		        ValueFromRemainingArguments = $true,
		        HelpMessage = "Array of image file names to convert to JPEG")]
		    [Alias("FullName")]
		    [String[]]$Files,
		    
            [Parameter(HelpMessage = "Destination folder, if not specified, source folder will be used")]
		    [String]$Folder,
			
		    [Parameter(HelpMessage = "Resize image to the specified horizontal size")]
		    [ValidateRange(0,10000)]
			[Int]$ScaleXto,			

		    [Parameter(HelpMessage = "Resize image to the specified vertical size")]
		    [ValidateRange(0,10000)]
			[Int]$ScaleYto,

		    [Parameter(HelpMessage = "Resize image by percent")]
		    [ValidateRange(-99,400)]
			[Int]$Scale,

		    [Parameter(HelpMessage = "suppress aspect ratio enforcement ")]
		    [Switch]$NoRatio,

		    [Parameter(HelpMessage = "Fix extension of JPEG/PNG files without the .jpg or .png extension")]
		    [Switch]$FixExtension,
			
			[Parameter(HelpMessage = "Convert files to JPEG image format (Default, if not set")]
		    [Switch]$Jpeg,
			
			[Parameter(HelpMessage = "Convert files to PNG image format (Default, is JPEG")]
		    [Switch]$Png			
			
		)

		Begin
		{
		    # Technique for await-ing WinRT APIs: https://fleexlab.blogspot.com/2018/02/using-winrts-iasyncoperation-in.html
		    Add-Type -AssemblyName System.Runtime.WindowsRuntime
		    $runtimeMethods = [System.WindowsRuntimeSystemExtensions].GetMethods()
		    $asTaskGeneric = ($runtimeMethods | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
		    Function AwaitOperation ($WinRtTask, $ResultType)
		    {
		        $asTaskSpecific = $asTaskGeneric.MakeGenericMethod($ResultType)
		        $netTask = $asTaskSpecific.Invoke($null, @($WinRtTask))
		        $netTask.Wait() | Out-Null
		        $netTask.Result
		    }
		    $asTask = ($runtimeMethods | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
		    Function AwaitAction ($WinRtTask)
		    {
		        $netTask = $asTask.Invoke($null, @($WinRtTask))
		        If (-not $netTask.IsCompleted) {$netTask.Wait() | Out-Null}
		    }

		    # Reference WinRT assemblies
		    [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
		    [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType=WindowsRuntime] | Out-Null
		}

		Process
		{
		    #Manage Parameters
			If ((-not $Jpeg) -and (-not $Png)) {$Jpeg = $true}
			If ($Jpeg -and $Png) {$Jpeg = $true ; $Png = $false}
			If ($Jpeg) {$FileEXT = ".jpg"; $EncoderID = "JpegEncoderId" ; $DecoderID = "JpegDecoderId" ; $Thumbnail = $true}
			If ($Png) {$FileEXT = ".png" ; $EncoderID = "PngEncoderId" ; $DecoderID = "PngDecoderId" ; $Thumbnail = $false }
						
						
			# Summary of imaging APIs: https://docs.microsoft.com/en-us/windows/uwp/audio-video-camera/imaging
		    foreach ($file in $Files)
		    {
		        Write-Host $file -NoNewline
		        try
		        {
		            try
		            {
		                # Get SoftwareBitmap from input file
		                $inputFile = AwaitOperation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($file)) ([Windows.Storage.StorageFile])
		                $inputFolder = AwaitOperation ($inputFile.GetParentAsync()) ([Windows.Storage.StorageFolder])
		                $inputStream = AwaitOperation ($inputFile.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
		                $decoder = AwaitOperation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($inputStream)) ([Windows.Graphics.Imaging.BitmapDecoder])
                        If ($Folder) 
                            {
                                If (-not (test-path $Folder)){New-Item -ItemType directory -Path $folder }
                                $OutputFolder = AwaitOperation ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($folder)) ([Windows.Storage.StorageFolder])
                            }
		            }
		            catch
		            {
		                # Ignore non-image files
		                Write-Host " [Unsupported]"
		                continue
		            }
		            if ($decoder.DecoderInformation.CodecId -eq [Windows.Graphics.Imaging.BitmapDecoder]::$DecoderID)
		            {
		                $extension = $inputFile.FileType
		                if (($FixExtension -and $Jpeg -and ($extension -ne ".jpg") -and ($extension -ne ".jpeg")) -or ($FixExtension -and $Png))
		                {
		                    # Rename JPEG-encoded files to have ".jpg" extension
							$newName = $inputFile.Name -replace ($extension + "$"), $FileEXT
		                    AwaitAction ($inputFile.RenameAsync($newName))
		                    Write-Host " => $newName"
		                }
		                else
		                {
		                    # Skip JPEG-encoded files
		                    Write-Host " [Already JPEG]"
		                }
		                
						# skip to next item if no resize is needed
						If ($ScaleXto -or $ScaleYto) {If(-not $Folder){$Sufix= "-Fx"}}
						Else {continue}
		            }
		            $bitmap = AwaitOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
					$PixelWidth = $bitmap.get_PixelWidth()
					$PixelHeight = $bitmap.get_PixelHeight()
					
					
					#Calculate scale with aspect ratio
					
					If (-not $Scale)
						{
							If ($ScaleXto -le 0 -or $ScaleXto -ge 10000){Write-Host "Scale value out of range, unable to proceed!!!" ; Exit}
							If ($ScaleYto -le 0 -or $ScaleYto -ge 10000){Write-Host "Scale value out of range, unable to proceed!!!" ; Exit}
						}	
					
					
					If (-not $NoRatio)
						{
							If (($ScaleXto -ge 1) -and ($ScaleYto -ge 1 ))
								{
									If ($PixelWidth -gt $PixelHeight){$ScaleRatio = $PixelWidth/$ScaleXto}
									Else {$ScaleRatio = $PixelHeight/$ScaleYto}	
									
									$ScaleX = [math]::Round([Int]$PixelWidth/$ScaleRatio)
									$ScaleY = [math]::Round([Int]$PixelHeight/$ScaleRatio)
								}
								
								
							If (($ScaleXto -ge 1 -and -not $ScaleYto) -or ($ScaleYto -ge 1 -and -not $ScaleXto))
								{
									If ($ScaleXto -ge 1){$ScaleRatio = $PixelWidth/$ScaleXto}
									Else {$ScaleRatio = $PixelHeight/$ScaleYto}	
									
									$ScaleX = [math]::Round([Int]$PixelWidth/$ScaleRatio)
									$ScaleY = [math]::Round([Int]$PixelHeight/$ScaleRatio)
								}
								
								
							If ($Scale -and ($ScaleXto -or $ScaleYto))
								{
									Write-Host "You can't use -scale and -PxWidth/PxHeight all together."
									Exit
								}
								
							If ($Scale -and (-not($ScaleXto -or $ScaleYto)))
								{	
									$ScaleX = [math]::Round([Int](($PixelWidth*$Scale)/100)+$PixelWidth)
									$ScaleY = [math]::Round([Int](($PixelHeight*$Scale)/100)+$PixelHeight)
								}
						}
					Else
						{
					
							If ($ScaleXto -ge 1){$ScaleX = $ScaleXto}
							IF ($ScaleYto -ge 1){$ScaleY = $ScaleYto}
						}
						
						
		            # Write SoftwareBitmap to output file
		            $outputFileName = $inputFile.DisplayName + $Sufix + $FileEXT
		            If ($Folder){$outputFile = AwaitOperation ($OutputFolder.CreateFileAsync($outputFileName, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])}
                    Else {$outputFile = AwaitOperation ($inputFolder.CreateFileAsync($outputFileName, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])}
		            $outputTransaction = AwaitOperation ($outputFile.OpenTransactedWriteAsync()) ([Windows.Storage.StorageStreamTransaction])
		            $outputStream = $outputTransaction.Stream
		            $encoder = AwaitOperation ([Windows.Graphics.Imaging.BitmapEncoder]::CreateAsync([Windows.Graphics.Imaging.BitmapEncoder]::$EncoderID, $outputStream)) ([Windows.Graphics.Imaging.BitmapEncoder])
		            $encoder.SetSoftwareBitmap($bitmap)
					If ($ScaleX -ge 1){$encoder.BitmapTransform.ScaledWidth = $ScaleX}
					If ($ScaleX -ge 1){$encoder.BitmapTransform.ScaledHeight = $ScaleY}
					#$encoder.BitmapTransform.InterpolationMode = [Windows.Graphics.Imaging.BitmapInterpolationMode]::Fant
		            $encoder.IsThumbnailGenerated = $Thumbnail

		            # Do it
		            AwaitAction ($encoder.FlushAsync())
		            Write-Host " -> $outputFileName"
		        }
		        catch
		        {
		            # Report full details
		            throw $_.Exception.ToString()
		        }
		        finally
		        {
		            # Clean-up
		            if ($inputStream -ne $null) { [System.IDisposable]$inputStream.Dispose() }
		            if ($outputStream -ne $null) { [System.IDisposable]$outputStream.Dispose() }
		            if ($outputTransaction -ne $null) { [System.IDisposable]$outputTransaction.Dispose() }
		        }
		    }
		}
#	}