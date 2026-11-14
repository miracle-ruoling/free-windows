Get-Counter -ListSet * -ErrorAction SilentlyContinue |
  Where-Object { $_.CounterSetName -match 'GPU|gpu' } |
  Select-Object -ExpandProperty CounterSetName
