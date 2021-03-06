. ./Zoo.ps1
Set-StrictMode -Version Latest

task BsonTypes {
	$1 = New-BsonBag

	# round trip Mdbc.Dictionary -> DB -> Mdbc.Dictionary
	Connect-Mdbc -NewCollection
	$1 | Add-MdbcData
	$2 = Get-MdbcData
	equals $1 $2
	assert ($1 -eq $2)

	# round trip Mdbc.Dictionary -> DB -> PS -> Mdbc.Dictionary
	$r = Get-MdbcData -As PS
	equals $r.double 3.14
	equals $r.string bar
	equals $r.object.GetType() ([System.Management.Automation.PSCustomObject])
	equals $r.array.GetType() ([System.Collections.ArrayList])
	equals $r.binData04 ([guid]"cdccdb76-30a3-4d7c-97fa-5ae1ad28fd64")
	equals $r.binData00.GetType() ([MongoDB.Bson.BsonBinaryData])
	equals $r.objectId.GetType() ([MongoDB.Bson.ObjectId])
	equals $r.bool $true
	equals $r.date ([DateTime]'2019-11-11')
	equals $r.null $null
	equals $r.regex.GetType() ([MongoDB.Bson.BsonRegularExpression])
	equals $r.javascript.GetType() ([MongoDB.Bson.BsonJavaScript])
	equals $r.javascriptWithScope.GetType() ([MongoDB.Bson.BsonJavaScriptWithScope])
	equals $r.int 42
	equals $r.timestamp.GetType() ([MongoDB.Bson.BsonTimestamp])
	equals $r.long 42L
	equals $r.decimal 123456789.123456789d
	equals $r.minKey ([MongoDB.Bson.BsonMinKey]::Value)
	equals $r.maxKey ([MongoDB.Bson.BsonMaxKey]::Value)
	$3 = New-MdbcData $r
	equals $1 $3
	assert ($1 -eq $3)

	# What we can get -As object, ExpandoObject
	$r = Get-MdbcData -As ([object]) -Project '{binData00: 0, regex: 0, javascript: 0, javascriptWithScope: 0, timestamp: 0, minKey: 0, maxKey: 0}'
	equals $r.GetType() ([System.Dynamic.ExpandoObject])
	equals $r.double 3.14
	equals $r.string bar
	equals $r.object.GetType() ([System.Dynamic.ExpandoObject]) #!
	equals $r.array.GetType() ([System.Collections.Generic.List[object]]) #!
	equals $r.binData04 ([guid]"cdccdb76-30a3-4d7c-97fa-5ae1ad28fd64")
	equals $r.objectId.GetType() ([MongoDB.Bson.ObjectId])
	equals $r.bool $true
	equals $r.date ([DateTime]'2019-11-11')
	equals $r.null $null
	equals $r.int 42
	equals $r.long 42L
	equals $r.decimal ([MongoDB.Bson.Decimal128]123456789.123456789d) #!
}

task DictionaryConstructors {
	# default
	$r = New-Object Mdbc.Dictionary
	equals $r.Count 0
	assert $r.ToBsonDocument()

	# from BsonDocument (wrapper)
	$d = New-Object MongoDB.Bson.BsonDocument
	$r = [Mdbc.Dictionary]$d.Add('name', 'name1') # `Add` gets the document
	equals $r.Count 1
	equals $r.name name1

	# from IDictionary
	$r = [Mdbc.Dictionary]@{_id = 42}
	equals $r.Count 1
	equals $r._id 42

	# Mdbc.Dictionary deep clone
	$arr = [MongoDB.Bson.BsonArray]@(1)
	$r1 = [Mdbc.Dictionary]@{p1 = $arr}
	$r2 = [Mdbc.Dictionary]$r1 #! trap, it's cast, not copy
	assert ([object]::ReferenceEquals($r1, $r2))
	# so use true constructor
	$r2 = [Mdbc.Dictionary]::new($r1)
	$doc2 = $r2.ToBsonDocument()
	equals "$doc2" p1=[1]
	assert (!([object]::ReferenceEquals($doc2, $r1.ToBsonDocument())))
	equals $doc2 $r1.ToBsonDocument()
	$arr2 = $doc2['p1']
	equals $arr2.ToString() [1]
	assert (!([object]::ReferenceEquals($arr2, $arr)))
	equals $arr2 $arr

	# from bad object, retired Mdbc.Dictionary(object)
	#! keep `[Mdbc.Dictionary]1`, ensure the error is this, not "cannot
	#! deserialize", see comments for .FromJson (why .Parse is not used)
	Test-Error { [Mdbc.Dictionary]1 } -Text 'Cannot convert the "1" value of type "System.Int32" to type "Mdbc.Dictionary".'
	Test-Error { [Mdbc.Dictionary]([version]1.1) } -Text 'Cannot convert the "1.1" value of type "System.Version" to type "Mdbc.Dictionary".'
}

task CollectionConstructors {
	# [object], used to allow this -- bad idea, PS converts [int] to [string]
	Test-Error {[Mdbc.Collection]1} -Text 'Cannot convert the "1" value of type "System.Int32" to type "Mdbc.Collection".'

	# ICollection
	$r = [Mdbc.Collection](1, @{x = 1})
	equals $r.ToString() '[1, { "x" : 1 }]'
	#! PowerShell does not call .ToString() on collection but calls on items
	equals "$r" '1 { "x" : 1 }'

	# BsonArray
	$arr = [MongoDB.Bson.BsonArray](1, 2)
	$r = [Mdbc.Collection]$arr
	assert ([object]::ReferenceEquals($arr, $r.ToBsonArray()))

	# Mdbc.Collection, deep clone
	$arr1 = [MongoDB.Bson.BsonArray]@(1)
	$arr2 = [MongoDB.Bson.BsonArray]@(, $arr1)
	$r1 = [Mdbc.Collection]$arr2
	$r2 = [Mdbc.Collection]$r1 #! trap, it's cast, not copy
	assert ([object]::ReferenceEquals($r1, $r2))
	# so use true constructor
	$r2 = [Mdbc.Collection]::new($r1)
	equals $r2.ToString() [[1]]

	$copy2 = $r2.ToBsonArray()
	equals $copy2.ToString() [[1]]
	equals $copy2 $arr2
	assert (!([object]::ReferenceEquals($arr2, $copy2)))

	$copy1 = $copy2[0]
	equals $copy1.ToString() [1]
	equals $copy1 $arr1
	assert (!([object]::ReferenceEquals($arr1, $copy1)))
}

# v4.8.0
task GetMissing {
	$d = New-MdbcData

	# get missing as null by []
	equals $d['missing']

	# dot notation fails in strict mode
	$$ = try { $d.missing } catch {$_}
	# v2,3 : Property...
	# v4   : The property...
	assert ($$ -like "*property 'missing' cannot be found on this object.*")
}

# $null should be preserved
task SetNull {
	$d = New-MdbcData @{x = 1; y = 2}
	$d.x = $null
	equals $d.Count 2
	equals $d.x
}

task RawBson {
	# RawBsonDocument
	Connect-Mdbc -NewCollection
	@{array = 1, 2; document = @{name = 42}} | Add-MdbcData
	$raw = Get-MdbcData -As ([MongoDB.Bson.RawBsonDocument])
	Test-Type $raw MongoDB.Bson.RawBsonDocument

	#_131015_123005 New-MdbcData makes new even on read only RawBsonDocument
	$md = New-MdbcData $raw
	assert (!$md.IsFixedSize)
	assert (!$md.IsReadOnly)
	Test-Type $md.ToBsonDocument() MongoDB.Bson.BsonDocument

	#
	$md = [Mdbc.Dictionary]$raw
	assert ($md.IsFixedSize)
	assert ($md.IsReadOnly)
	Test-Type $md.ToBsonDocument() MongoDB.Bson.RawBsonDocument

	&{
		$a = $md.array
		assert ($a.IsFixedSize)
		assert ($a.IsReadOnly)
		assert ($a.ToBsonArray().IsReadOnly) # fixed https://jira.mongodb.org/browse/CSHARP-842
		Test-Type $a.ToBsonArray() MongoDB.Bson.RawBsonArray
		assert (![object]::ReferenceEquals($a.ToBsonArray(), $md.array.ToBsonArray()))
	}

	&{
		$d = $md.document
		assert ($d.IsFixedSize)
		assert ($d.IsReadOnly)
		Test-Type $d.ToBsonDocument() MongoDB.Bson.RawBsonDocument
		assert (![object]::ReferenceEquals($d.ToBsonDocument(), $md.document.ToBsonDocument()))
	}
}

#_120509_173140 BsonBinaryData and byte[] consideration.
# We used to map to byte[] then reverted to BsonBinaryData except Guid.
task Binary {
	# byte[] ~ BsonBinaryData
	$data1 = New-MdbcData
	$data1._id = [byte[]](1..5)
	$id1 = $data1._id
	equals ($id1.ToString()) Binary:0x0102030405
	equals ($id1.GetType().FullName) MongoDB.Bson.BsonBinaryData

	# comparison operator works
	$data2 = New-MdbcData -Id ([byte[]](1..5))
	assert ($id1 -eq $data2._id)

	# but UUID ~ guid
	$data3 = New-MdbcData -Id ([guid]'9c700f34-e28d-416d-8aa8-eb55f7781565')
	equals ($data3._id.ToString()) 9c700f34-e28d-416d-8aa8-eb55f7781565
	equals ($data3._id.GetType().FullName) System.Guid
	$doc3 = $data3.ToBsonDocument()
	equals ($doc3['_id'].SubType) ([MongoDB.Bson.BsonBinarySubType]::UuidStandard)

	# assign from .NET to document
	$data4 = New-MdbcData -Id $id1
	$data4.p1 = $id1
	equals $data4._id $id1
	equals $data4.p1 $id1
}

#_120509_173140 BsonRegularExpression and Regex consideration.
# We can map BsonRegularExpression to Regex but the gain is not clear.
# BsonRegularExpression does not parse patterns, the server does, so it's effective.
task Regex {
	# .NET Regex
	$regex = [regex]::new('bar', 'IgnoreCase')

	# Regex is mapped to BsonRegularExpression automatically
	# BsonRegularExpression has .Pattern .Options, converted to Regex by ToRegex()
	$r1 = New-MdbcData
	$r1.p1 = $regex
	$re = $r1.p1
	equals $re.GetType() ([MongoDB.Bson.BsonRegularExpression])
	equals $re.ToString() /bar/i
	equals $re.Pattern bar
	equals $re.Options i
	$re1 = $r1.p1.ToRegex()
	equals $re1.GetType() ([regex])

	# test trip to bson file
	$r1 | Export-MdbcData z.bson
	$r2 = Import-MdbcData z.bson
	$re = $r1.p1
	equals $re.GetType() ([MongoDB.Bson.BsonRegularExpression])
	equals $re.ToString() /bar/i
	equals $re.Pattern bar
	equals $re.Options i
	$re2 = $r2.p1.ToRegex()
	equals $re2.GetType() ([regex])

	# BsonRegularExpression - comparison works
	equals $r1.p1 $r2.p1

	# Regex - comarison is not working
	equals ($re1 -eq $re2) $false

	remove z.bson
}

task BsonRegularExpression_facts {
	# In BsonRegularExpression(re) mind `/.../` syntax for options.
	# To specify literal `/bar/`, escape the first / or use others.
	$r = [MongoDB.Bson.BsonRegularExpression]'/bar/'
	equals $r.Pattern bar

	# In BsonRegularExpression(re, op), `re` is literal pattern.
	$r = [MongoDB.Bson.BsonRegularExpression]::new('/bar/', $null)
	equals $r.Pattern /bar/

	# [regex] may be used, too, it's literally converted
	$r = [MongoDB.Bson.BsonRegularExpression][regex]'/bar/'
	equals $r.Pattern /bar/
}

#_120509_173140 [decimal] <-> BsonDecimal128
task Decimal {
	$1 = [Mdbc.Dictionary]::new()

	# decimal ~ BsonDecimal128
	$1.p1 = 123.123d
	equals ($1.p1.GetType()) ([decimal])
	equals ($1.ToBsonDocument()['p1'].GetType()) ([MongoDB.Bson.BsonDecimal128])

	Connect-Mdbc -NewCollection
	$1 | Add-MdbcData
	$2 = Get-MdbcData
	equals $1 $2
	equals $1.p1 $2.p1

	$1 | Export-MdbcData z.bson
	$2 = Import-MdbcData z.bson
	equals $1 $2
	equals $1.p1 $2.p1

	remove z.bson
}

# v6.5.1
task FromJsonAndEnsureId {
	$r = [Mdbc.Dictionary]::FromJson('{"name": "bar"}')
	equals $r.GetType() ([Mdbc.Dictionary])
	equals $r.Count 1
	equals $r.name bar

	$r.EnsureId()
	equals ($r.Keys -join '|') '_id|name'
	equals $r._id.GetType() ([MongoDB.Bson.ObjectId])
}
