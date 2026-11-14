$p = (Get-Counter -ListSet "GPU Engine").Paths[0]
"path: $p"
try { $s = (Get-Counter -Counter $p -ErrorAction Stop).CounterSamples; "samples: " + $s.Count; $s | Select-Object -First 3 InstanceName,CookedValue | Format-Table -AutoSize }
catch { "err: " + $_.Exception.Message }
