
Function foo {
    $ErrorActionPreference = 'stop'
    return "foo $(bar)"
}