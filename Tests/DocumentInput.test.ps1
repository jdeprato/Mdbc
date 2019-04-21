
<#
.Synopsis
	Common tests for New-MdbcData, Add-MdbcData, Export-MdbcData
#>

. .\Zoo.ps1
Import-Module Mdbc
Set-StrictMode -Version Latest
Connect-Mdbc

task BsonValueError {
	# good data to be done regardless of errors
	$good = @{_id = 1; Name = 'name1'}, @{_id = 2; Name = 'name2'}

	# bad data inserted before good
	$bad = @($Host) + $good

	Invoke-Test {
		assert ($e -like '.NET type * cannot be mapped to a BsonValue.')
		equals $Host $e.TargetObject
		Test-List -Force $r $good
	}{
		$r = $bad | New-MdbcData -ErrorAction 0 -ErrorVariable e
	}{
		$null = $Collection.RemoveAll()
		$bad | Add-MdbcData -ErrorAction 0 -ErrorVariable e
		$r = Get-MdbcData
	}{
		$bad | Export-MdbcData -ErrorAction 0 -ErrorVariable e -Path z.bson
		$r = Import-MdbcData z.bson
	}

	Remove-Item z.bson
}

task IdParameters {
	# input object
	$ps = New-Object PSObject -Property @{ id = 'id1'; name = 'name1' }

	Invoke-Test {
		Test-Error {test -NewId -Id 'bad' -ErrorAction 0} 'Parameters Id and NewId cannot be used together.'

		# Create with value
		$d = test -Id 'value'
		equals $d.Count 3
		equals $d._id 'value'

		# Create with script
		$d = test -Id {$_.Id}
		equals $d.Count 3
		equals $d._id 'id1'

		# Generate _id
		$d = test -NewId
		equals $d.Count 3
		assert ($d._id -is [MongoDB.Bson.ObjectId])
	}{
		function test([switch]$NewId, $Id, $ErrorAction) {
			New-MdbcData $ps @PSBoundParameters
		}
	}{
		function test([switch]$NewId, $Id, $ErrorAction) {
			$null = $Collection.RemoveAll()
			Add-MdbcData $ps @PSBoundParameters
			Get-MdbcData
		}
	}{
		function test([switch]$NewId, $Id, $ErrorAction) {
			$ps | Export-MdbcData z.bson @PSBoundParameters
			Import-MdbcData z.bson
		}
	}

	Remove-Item z.bson
}

#_131013_155413
task DocumentAsInput {
	$mdbc = New-MdbcData @{x = 42; y = 0;}
	$bson = $mdbc.ToBsonDocument()
	equals $mdbc.Count 2

	# new, even if it is a copy
	$mdbc1 = $mdbc | New-MdbcData
	equals $mdbc1.Count 2
	assert (![object]::ReferenceEquals($mdbc1.ToBsonDocument(), $bson))

	# new and only x is there
	$mdbc2 = $mdbc | New-MdbcData -Property x
	equals $mdbc2.Count 1
	assert (![object]::ReferenceEquals($mdbc2.ToBsonDocument(), $bson))

	# new and only x is there
	$mdbc2 = , $bson | New-MdbcData -Property x
	assert ($mdbc2.Count -eq 1) $mdbc2.Count
	assert (![object]::ReferenceEquals($mdbc2.ToBsonDocument(), $bson))

	# new and _id is added
	$mdbc3 = $mdbc | New-MdbcData -Id 3
	equals $mdbc3.Count 3
	equals $mdbc3._id 3
	assert (![object]::ReferenceEquals($mdbc3.ToBsonDocument(), $bson))

	# new and _id is added
	$mdbc4 = , $bson | New-MdbcData -Id 4
	equals $mdbc4.Count 3
	equals $mdbc4._id 4
	assert (![object]::ReferenceEquals($mdbc4.ToBsonDocument(), $bson))

	# terminating error on duplicate _id
	Test-Error {$mdbc4 | New-MdbcData -NewId -ErrorAction 0} "Duplicate element name '_id'."
	Test-Error {$mdbc4 | New-MdbcData -Id 3 -ErrorAction 0} "Duplicate element name '_id'."
	Test-Error {@{_id=1} | New-MdbcData -NewId -ErrorAction 0} "Duplicate element name '_id'."
	Test-Error {@{_id=1} | New-MdbcData -Id 3 -ErrorAction 0} "Duplicate element name '_id'."

	# + see _131015_123005 for New-MdbcData makes new even on RawBsonDocument
}
