# 학생 PC 에서 원격 실행되어 정보를 한 줄(JSON)로 돌려준다 - Teacher.ps1 이 읽어서 표에 채운다
$os = Get-CimInstance Win32_OperatingSystem
$cpu = [int](Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
$mem = [int](100 * ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize)
$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$disk = if ($d.Size) { [int](100 * ($d.Size - $d.FreeSpace) / $d.Size) } else { 0 }
$mac = ''
try { $mac = (Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up' | Select-Object -First 1).MacAddress } catch {}
$ver = ''
try { $ver = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion } catch {}
$frz = '미설치'
try {
    $f = Get-CimInstance -Namespace 'root\standardcimv2\embedded' -ClassName UWF_Filter -ErrorAction Stop
    $now = if ($f.CurrentEnabled) { '켜짐' } else { '꺼짐' }
    $next = if ($f.NextEnabled) { '켜짐' } else { '꺼짐' }
    $frz = if ($now -eq $next) { $now } else { "$now (재부팅 후 $next)" }
} catch {}
$ip = ''
try {
    $rt = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric | Select-Object -First 1
    $ip = (Get-NetIPAddress -InterfaceIndex $rt.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1).IPAddress
} catch {}
$name = ($os.Caption -replace 'Microsoft ', '')
$o = [ordered]@{ os = ("{0} {1} ({2})" -f $name, $ver, $os.Version); mac = $mac; ip = $ip; freeze = $frz; cpu = $cpu; mem = $mem; disk = $disk }
Write-Output ('@@' + 'INFO@@' + ($o | ConvertTo-Json -Compress))