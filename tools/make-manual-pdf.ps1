<#
Makes the PDF manual from the HTML documentation in bin/Doc.

The chapters (the pages of the navigation, in its order) are put into one
print document: the header and footer lines of the pages are left out, the
anchors get the name of their page as a prefix, so the links between the
pages become links inside the PDF. Microsoft Edge (headless) prints it to
bin/Doc/DBDesignerFork_manual.pdf, with a table of contents,
bookmarks and page numbers. The version is the one on the start page.

Run it from the project directory after a change of the documentation:

    powershell -ExecutionPolicy Bypass -File tools\make-manual-pdf.ps1
#>
param(
  [string]$Edge = ''
)

$ErrorActionPreference = 'Stop'

$DocDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin\Doc'
$Chapters = @('info', 'fundamentals', 'modelling', 'querying', 'ui', 'editors',
  'db', 'plugins', 'mcp', 'shortcuts', 'history', 'license')

if($Edge -eq '')
{
  foreach($Candidate in @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"))
  {
    if(Test-Path $Candidate) { $Edge = $Candidate; break }
  }
}
if(($Edge -eq '') -or -not (Test-Path $Edge))
{
  throw 'Microsoft Edge (or Google Chrome) was not found; pass its path with -Edge.'
}

# The pages are ASCII, history.html is windows-1252 (its old bullets)
$Ansi = [System.Text.Encoding]::GetEncoding(1252)
function Read-Page([string]$Name)
{
  return [System.IO.File]::ReadAllText((Join-Path $DocDir "$Name.html"), $Ansi)
}

$Start = Read-Page 'start'
if($Start -match 'Version\s+([0-9][0-9.]*)') { $Version = $Matches[1] }
else { throw 'No version on start.html' }

$Opt = [System.Text.RegularExpressions.RegexOptions]'Singleline, IgnoreCase'

function Strip-Tags([string]$Html)
{
  $Text = [regex]::Replace($Html, '<[^>]+>', '')
  $Text = $Text -replace '&amp;', '&' -replace '&nbsp;', ' '
  return ($Text -replace '\s+', ' ').Trim()
}

$Toc = New-Object System.Text.StringBuilder
$Body = New-Object System.Text.StringBuilder

foreach($Page in $Chapters)
{
  $Html = Read-Page $Page
  $Html = [regex]::Match($Html, '<body[^>]*>(.*)</body>', $Opt).Groups[1].Value

  # Header and footer line of the page (the tables with the brand)
  $Html = [regex]::Replace($Html,
    '<table[^>]*>(?:(?!</table>).)*?DocBrand(?:(?!</table>).)*?</table>', '', $Opt)

  # Anchors: <a name="x"> -> <a id="page-x">, the PDF links need ids
  $Html = [regex]::Replace($Html, '<a\s+name="([^"]+)"',
    { param($m) '<a id="' + $Page + '-' + $m.Groups[1].Value + '"' }, $Opt)

  # Links: #x -> #page-x (first, the others then start with # too),
  # other.html#x -> #other-x, other.html -> #other
  $Html = [regex]::Replace($Html, 'href="#([^"]+)"',
    { param($m) 'href="#' + $Page + '-' + $m.Groups[1].Value + '"' }, $Opt)
  $Html = [regex]::Replace($Html, 'href="([a-z_]+)\.html#([^"]+)"',
    { param($m) 'href="#' + $m.Groups[1].Value + '-' + $m.Groups[2].Value + '"' }, $Opt)
  $Html = [regex]::Replace($Html, 'href="([a-z_]+)\.html"',
    { param($m) 'href="#' + $m.Groups[1].Value + '"' }, $Opt)
  # Links inside the PDF open no new window
  $Html = $Html -replace '(href="#[^"]*")\s+target="_blank"', '$1'

  # Table of contents: the chapter and its sections with an anchor
  $Title = Strip-Tags ([regex]::Match($Html, '<h2[^>]*>(.*?)</h2>', $Opt).Groups[1].Value)
  [void]$Toc.AppendLine("<li><a href=""#$Page"">$Title</a>")
  $Sections = [regex]::Matches($Html, '<h3[^>]*>\s*<a id="([^"]+)"[^>]*>(.*?)</a>', $Opt)
  if($Sections.Count -gt 0)
  {
    [void]$Toc.AppendLine('<ul>')
    foreach($Section in $Sections)
    {
      [void]$Toc.AppendLine('<li><a href="#' + $Section.Groups[1].Value + '">' +
        (Strip-Tags $Section.Groups[2].Value) + '</a></li>')
    }
    [void]$Toc.AppendLine('</ul>')
  }
  [void]$Toc.AppendLine('</li>')

  [void]$Body.AppendLine("<div class=""Chapter"" id=""$Page"">")
  [void]$Body.AppendLine($Html)
  [void]$Body.AppendLine('</div>')
}

$Document = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>DBDesigner Fork $Version - Manual</title>
<link rel="StyleSheet" href="document.css" type="text/css">
<style type="text/css">
  @page {
    size: A4;
    margin: 18mm 16mm 18mm 16mm;
    @top-right { content: "DBDesigner Fork $Version"; font: 8px Verdana, Arial, sans-serif; color: #666666; }
    @bottom-center { content: counter(page); font: 9px Verdana, Arial, sans-serif; color: #666666; }
  }
  @page :first {
    @top-right { content: none; }
    @bottom-center { content: none; }
  }
  body { margin: 0; }
  .TitlePage { height: 240mm; display: flex; flex-direction: column; justify-content: center; text-align: center; }
  .TitlePage .Name { color: #003366; font-size: 44px; font-weight: bold; }
  .TitlePage .Sub { font-size: 16px; margin-top: 8px; }
  .TitlePage .Small { font-size: 11px; color: #666666; margin-top: 40px; line-height: 1.6; }
  .Toc { break-before: page; }
  .Toc ul { list-style: none; padding-left: 0; }
  .Toc ul ul { padding-left: 20px; margin-bottom: 6px; }
  .Toc li { font-size: 12px; margin: 2px 0; }
  .Toc > ul > li > a { font-weight: bold; }
  .Toc a { color: #000000; text-decoration: none; }
  .Chapter { break-before: page; }
  .Chapter > h2.Heading1:first-of-type { margin-top: 0; }
  img { max-width: 100%; height: auto; }
  h2, h3, h4, h5 { break-after: avoid; }
  p.ImageSubTitle, table, li { break-inside: avoid; }
</style>
</head>
<body>
<div class="TitlePage">
  <div class="Name">DBDesigner Fork</div>
  <div class="Sub">Manual &middot; Version $Version</div>
  <div class="Small">
    Visual database design for MySQL, SQLite and Firebird<br>
    https://github.com/Teimue/dbdesigner-fork<br><br>
    DBDesigner 4 &copy; 2003 fabFORCE.net &middot; DBDesigner Fork &copy; 2006-2026 the contributors &middot; GNU GPL
  </div>
</div>
<div class="Toc">
<h2 class="Heading1">Contents</h2>
<ul>
$($Toc.ToString())
</ul>
</div>
$($Body.ToString())
</body>
</html>
"@

# Next to the pages, so the images and the style sheet are found
$PrintFile = Join-Path $DocDir '_manual_print.html'
$PdfFile = Join-Path $DocDir "DBDesignerFork_manual.pdf"
$EdgeProfile = Join-Path ([System.IO.Path]::GetTempPath()) 'dbdesigner-manual-edge'

[System.IO.File]::WriteAllText($PrintFile, $Document, (New-Object System.Text.UTF8Encoding $false))
try
{
  if(Test-Path $PdfFile) { Remove-Item $PdfFile }
  $Url = ([System.Uri]$PrintFile).AbsoluteUri
  # Start-Process passes the arguments as one line: paths with blanks in quotes
  $EdgeArgs = @('--headless', '--disable-gpu', '--no-first-run', "--user-data-dir=""$EdgeProfile""",
    '--no-pdf-header-footer', '--generate-pdf-document-outline',
    "--print-to-pdf=""$PdfFile""", """$Url""")
  $Process = Start-Process -FilePath $Edge -ArgumentList $EdgeArgs -Wait -PassThru -WindowStyle Hidden
  if(-not (Test-Path $PdfFile)) { throw "The browser wrote no PDF (exit code $($Process.ExitCode))." }
  Write-Host "Written: $PdfFile ($([math]::Round((Get-Item $PdfFile).Length / 1KB)) KB)"
}
finally
{
  Remove-Item $PrintFile -ErrorAction SilentlyContinue
}
