try {
  $s = (Get-Counter "GPU Engine(*)\Utilization Percentage" -ErrorAction Stop).CounterSamples
  "instances: " + $s.Count
  $s | Select-Object -First 4 InstanceName, CookedValue | Format-Table -AutoSize
} catch { "err: " + $_.Exception.Message }
