$ErrorActionPreference = 'stop'
$ModuleRootPath = (Get-Item -path $MyInvocation.MyCommand.Path).Directory.Parent.FullName
$ThisModuleName = (Get-Item -path $MyInvocation.MyCommand.Path).Directory.Parent.Name
write-host "Module root: $($ThisModuleName ) " -Verbose
$ModulePath = Join-Path $ModuleRootPath "$ThisModuleName.psm1"
Get-Module -Name $ThisModuleName | Remove-Module -Force -ErrorAction Ignore
write-host "Fully qualified path of module file: $($ModulePath ) " -Verbose
Import-Module -Name $ModulePath -Force -ErrorAction Stop
InModuleScope $ThisModuleName {
    Describe 'foo tests' {
        $result = Foo
        
        it 'Foo the foo' {
            $result | should be 'foo bar'
        }
    }
}