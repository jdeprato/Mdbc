﻿
. .\Zoo.ps1
Import-Module Mdbc

task Basics {
	# test relative paths
	Set-Location C:\TEMP

	$1 = New-MdbcData
	$1._id = 'Name1'
	$1.pr2 = 12345
	$1.pr3 = @{
		p4 = 'Name2'
		p5 = 67890
	}
	$1.имя = "имя1"

	$2 = @{
		_id = 'Name2'
		pr2 = 67890
		имя = "имя2"
	}

	$3 = @{
		_id = 'Name3'
		pr2 = 3.14
		имя = "имя3"
	}

	function Test-Dictionary3 {
		'[0]'
		Test-Table $data1[0] $data2[0]
		'[1]'
		Test-Table $data1[1] $data2[1]
		'[2]'
		Test-Table $data1[2] $data2[2]
	}

	# dump by mongodump
	Connect-Mdbc -NewCollection
	$1, $2, $3 | Add-MdbcData
	Set-Alias mongodump ([IO.Path]::GetDirectoryName((Get-Process mongod).Path) + '\mongodump.exe')
	exec {mongodump -d test -c test}

	# dump by mdbc
	$1, $2 | Export-MdbcData test2.bson
	Export-MdbcData test2.bson $3 -Append #! positional InputObject
	Import-MdbcData test2.bson -As PS | Format-Table -AutoSize | Out-String

	# the same file size
	$file1 = Get-Item dump\test\test.bson
	$file2 = Get-Item test2.bson
	equals $file1.Length $file2.Length

	# import both data for comparison
	$data1 = Import-MdbcData dump\test\test.bson
	$data2 = Import-MdbcData test2.bson
	Test-Dictionary3 $data1 $data2

	# restore from our dump
	Connect-Mdbc -NewCollection
	equals (Get-MdbcData -Count) 0L
	Set-Alias mongorestore ([IO.Path]::GetDirectoryName((Get-Process mongod).Path) + '\mongorestore.exe')
	exec { $ErrorActionPreference = 0; mongorestore -d test -c test test2.bson }
	$data2 = Get-MdbcData
	#! WiredTiger Win8: data restored not in the original order; Win7: fine.
	#! Weird? Maybe it's not guaranteed. Anyway, let's use SortBy.
	$data2 = Get-MdbcData -Sort '{_id : 1}'
	Test-Dictionary3 $data1 $data2

	# end
	Remove-Item test2.bson, dump -Recurse -Force
}

task Retry {
	Import-Module SplitPipeline
	$dataCount = 2000
	$pipeCount = 3

	Invoke-Test {
		remove $file

		1..$dataCount | Split-Pipeline -Verbose -Count $pipeCount -Variable file -Module Mdbc {process{
			@{_id=$_; data=[runspace]::DefaultRunspace.InstanceId} |
			Export-MdbcData -Verbose -Append -Retry (New-TimeSpan -Seconds 10) $file
		}}

		# all data are there
		$r = Import-MdbcData $file -As PS
		equals $r.Count $dataCount

		# all writers are there
		$r = $r | Group-Object data
		assert($r.Count -eq $pipeCount)

		Remove-Item -LiteralPath $file
	}{
		$file = "$env:TEMP\z.bson"
	}{
		$file = "$env:TEMP\z.json"
	}
}
