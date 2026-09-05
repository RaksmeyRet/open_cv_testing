$ErrorActionPreference = 'Stop'

$listenAddress = [System.Net.IPAddress]::Loopback
$listenPort = 8212
$targetHost = '157.245.49.153'
$targetPort = 8212

$listener = [System.Net.Sockets.TcpListener]::new($listenAddress, $listenPort)
$listener.Start()
Write-Host "OCR proxy listening on http://127.0.0.1:$listenPort"
Write-Host "Forwarding to http://${targetHost}:${targetPort}"

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $target = [System.Net.Sockets.TcpClient]::new()
            $target.Connect($targetHost, $targetPort)

            $clientStream = $client.GetStream()
            $targetStream = $target.GetStream()
            $clientToTarget = $clientStream.CopyToAsync($targetStream)
            $targetToClient = $targetStream.CopyToAsync($clientStream)
            [System.Threading.Tasks.Task]::WaitAny(@($clientToTarget, $targetToClient)) | Out-Null
        } catch {
            Write-Warning "OCR proxy request failed: $($_.Exception.Message)"
        } finally {
            if ($target) { $target.Dispose() }
            $client.Dispose()
        }
    }
} finally {
    $listener.Stop()
}
