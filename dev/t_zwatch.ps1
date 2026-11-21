# Task 1 probe: watch the z-order of our windows against everything else.
#
#   .\t_zwatch.ps1                        # 60 s baseline, one line per 250 ms
#   .\t_zwatch.ps1 -Seconds 600 -Tag bad  # 10 min while the user reproduces the bug
#   .\t_zwatch.ps1 -Once -Detail          # one full z-order dump (what is above us right now)
#
# What it answers, per sample:
#   * does each of our windows still carry WS_EX_TOPMOST?      (topmost=0 while visible -> we got demoted)
#   * at which z index does it sit?                            (z#n, smaller = higher on screen)
#   * which visible windows sit ABOVE it and overlap it?        (over=...)
#   * does a click at 5 points inside it land on us or on them? (hit=k/5, alpha-hit-test aware)
#   * what is in the foreground and is it a capture overlay?    (fg=..., overlay=YES)
#
# Layered windows are hit-tested by alpha, so a "miss" alone does not prove occlusion - the z index and
# the topmost flag are the authoritative evidence, hit= is corroboration.
param(
    [int]$Seconds = 60,
    [int]$IntervalMs = 250,
    [string]$Tag = 'run',
    [switch]$Once,
    [switch]$Detail
)
$ErrorActionPreference = 'Stop'

Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class ZW {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int v, int sz);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);

  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  public class Win {
    public IntPtr h; public int idx; public string cls = ""; public string title = "";
    public uint pid; public long ex; public RECT r; public bool vis, icon, cloak;
    public bool Topmost { get { return (ex & 0x8L) != 0; } }
    public int W { get { return r.Right - r.Left; } }
    public int H { get { return r.Bottom - r.Top; } }
    public bool Intersects(RECT o) {
      return r.Left < o.Right && o.Left < r.Right && r.Top < o.Bottom && o.Top < r.Bottom;
    }
  }

  public static List<Win> Snapshot() {
    var list = new List<Win>();
    EnumWindows((h, lp) => {
      var w = new Win(); w.h = h; w.idx = list.Count;
      var b = new StringBuilder(256); GetClassName(h, b, 256); w.cls = b.ToString();
      var t = new StringBuilder(256); GetWindowText(h, t, 160); w.title = t.ToString();
      GetWindowThreadProcessId(h, out w.pid);
      w.ex = (long)GetWindowLong(h, -20);
      GetWindowRect(h, out w.r);
      w.vis = IsWindowVisible(h); w.icon = IsIconic(h);
      int ck; w.cloak = DwmGetWindowAttribute(h, 14, out ck, 4) == 0 && ck != 0;
      list.Add(w);
      return true;
    }, IntPtr.Zero);
    return list;
  }

  static readonly string[] Ours = { "DockStripWindow", "DockTrayBarWindow", "DockGroupBoxWindow",
                                    "DockGridWindow", "DockSettingsWindow", "DockThumbWindow", "DockBgWindow" };
  public static bool IsOurs(string c) { return Array.IndexOf(Ours, c) >= 0; }

  public static string Overlay(string cls) {
    string s = cls.ToLowerInvariant();
    string[] keys = { "snip", "clip", "screen", "overlay", "captur", "magnif", "zoomit", "toolbar" };
    foreach (var k in keys) if (s.Contains(k)) return k;
    return "";
  }

  public static string Hit(IntPtr h, RECT r) {
    int[] fx = { 1, 5, 1, 5, 3 };   // *1/6: left, right, top, bottom, centre
    int[] fy = { 3, 3, 1, 5, 3 };
    int ok = 0; var others = new List<string>();
    for (int i = 0; i < 5; i++) {
      POINT p; p.X = r.Left + (r.Right - r.Left) * fx[i] / 6; p.Y = r.Top + (r.Bottom - r.Top) * fy[i] / 6;
      IntPtr at = GetAncestor(WindowFromPoint(p), 2);
      if (at == h) { ok++; continue; }
      var b = new StringBuilder(128); GetClassName(at, b, 128);
      string c = b.ToString(); if (c.Length == 0) c = "?";
      if (!others.Contains(c)) others.Add(c);
    }
    return ok + "/5" + (others.Count > 0 ? "[" + string.Join(",", others.ToArray()) + "]" : "");
  }

  public static string Fg(List<Win> list) {
    IntPtr f = GetForegroundWindow();
    foreach (var w in list) if (w.h == f)
      return w.cls + "|pid=" + w.pid + "|tm=" + (w.Topmost ? 1 : 0) + "|z#" + w.idx +
             (w.title.Length > 0 ? "|" + w.title.Replace("\n", " ").Replace("\t", " ") : "");
    return "(none)";
  }

  // one full dump of everything at or above the lowest of our visible windows
  public static string Dump(List<Win> list) {
    int lowest = -1; RECT union = new RECT();
    foreach (var w in list) {
      if (!IsOurs(w.cls) || !w.vis) continue;
      if (lowest < 0) union = w.r;
      else {
        if (w.r.Left < union.Left) union.Left = w.r.Left;
        if (w.r.Top < union.Top) union.Top = w.r.Top;
        if (w.r.Right > union.Right) union.Right = w.r.Right;
        if (w.r.Bottom > union.Bottom) union.Bottom = w.r.Bottom;
      }
      if (w.idx > lowest) lowest = w.idx;
    }
    var sb = new StringBuilder();
    if (lowest < 0) return "  (none of our windows is visible)\n";
    sb.Append("  our union rect " + union.Left + "," + union.Top + "-" + union.Right + "," + union.Bottom + "\n");
    foreach (var w in list) {
      if (w.idx > lowest) break;
      bool mine = IsOurs(w.cls);
      if (!mine && !w.vis) continue;
      if (!mine && !w.Intersects(union)) continue;
      string flag = mine ? "<<" : "  ";
      string ov = Overlay(w.cls);
      sb.Append(string.Format("  z#{0,-3} {1} {2,-34} pid={3,-6} tm={4} cloak={5} vis={6} icon={7} lay={8} {9},{10} {11}x{12} {13}{14}\n",
        w.idx, flag, w.cls.Length > 34 ? w.cls.Substring(0, 34) : w.cls, w.pid, w.Topmost ? 1 : 0,
        w.cloak ? 1 : 0, w.vis ? 1 : 0, w.icon ? 1 : 0, (w.ex & 0x80000L) != 0 ? 1 : 0,
        w.r.Left, w.r.Top, w.W, w.H, ov.Length > 0 ? ("OVERLAY='" + ov + "' ") : "",
        w.title.Length > 0 ? w.title : ""));
    }
    return sb.ToString();
  }

  public static string Sample(List<Win> list, bool detail) {
    var sb = new StringBuilder();
    bool bad = false;
    var union = new RECT(); bool haveUnion = false;
    var lines = new StringBuilder();
    foreach (string cls in new[] { "DockStripWindow", "DockTrayBarWindow", "DockGroupBoxWindow" }) {
      Win me = null;
      foreach (var w in list) if (w.cls == cls) { me = w; break; }
      if (me == null) { lines.Append(cls.Replace("Dock", "").Replace("Window", "").PadRight(8) + " absent  | "); continue; }
      if (!haveUnion) { union = me.r; haveUnion = true; }
      else {
        if (me.r.Left < union.Left) union.Left = me.r.Left;
        if (me.r.Top < union.Top) union.Top = me.r.Top;
        if (me.r.Right > union.Right) union.Right = me.r.Right;
        if (me.r.Bottom > union.Bottom) union.Bottom = me.r.Bottom;
      }
      // who is above us and overlaps us
      var cov = new List<string>();
      if (me.vis) {
        foreach (var w in list) {
          if (w.idx >= me.idx) break;
          if (IsOurs(w.cls)) continue;
          if (!w.vis || w.icon || w.cloak) continue;
          if (!w.Intersects(me.r)) continue;
          cov.Add("z#" + w.idx + ":" + w.cls + "(pid=" + w.pid + ",tm=" + (w.Topmost ? 1 : 0) + ")");
          bad = true;
        }
      }
      if (me.vis && !me.Topmost) bad = true;
      lines.Append(string.Format("{0} z#{1,-4} tm={2} vis={3} cloak={4} hit={5} over={6} | ",
        cls.Replace("Dock", "").Replace("Window", "").PadRight(8), me.idx, me.Topmost ? 1 : 0,
        me.vis ? 1 : 0, me.cloak ? 1 : 0, me.vis ? Hit(me.h, me.r) : "-",
        cov.Count > 0 ? string.Join("+", cov.ToArray()) : "-"));
    }
    string fg = Fg(list);
    string ovl = "";
    foreach (var w in list) {
      if (!w.vis || w.cloak) continue;
      string o = Overlay(w.cls);
      if (o.Length > 0 && w.Topmost) { ovl = w.cls + "(z#" + w.idx + "," + o + ")"; break; }
    }
    sb.Append(lines.ToString());
    sb.Append("fg=" + fg + (ovl.Length > 0 ? " overlay=" + ovl : "") + " => " + (bad ? "!! OCCLUDED" : "ok"));
    if (detail || bad) sb.Append("\n" + Dump(list).TrimEnd());
    return sb.ToString();
  }
}
"@

[void][ZW]::SetProcessDpiAwarenessContext([IntPtr](-4))

$out = Join-Path $PSScriptRoot ("zwatch_" + $Tag + "_" + (Get-Date -Format 'MMdd_HHmmss') + ".log")
function W($s) { Add-Content -LiteralPath $out -Value $s -Encoding UTF8 }

if ($Once) {
    $l = [ZW]::Snapshot()
    Write-Output ([ZW]::Dump($l))
    Write-Output ("sample: " + [ZW]::Sample($l, $true))
    exit 0
}

W ("# zwatch tag=$Tag interval=${IntervalMs}ms seconds=$Seconds pid(dock)=" +
   ((Get-Process dock -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Id) -join ','))
W ("# started " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'))
W ("# header: <win> z#<index global top-to-bottom> tm=<still WS_EX_TOPMOST> vis= cloak= hit=<points landing on
#  us>[<classes that took them>] over=<visible overlapping windows above us in z> fg=<foreground>")
W ("# --- full z-order at start ---")
W ([ZW]::Dump([ZW]::Snapshot()).TrimEnd())

$t0 = Get-Date
$last = ''
$lastDump = Get-Date
$samples = 0
$badSamples = 0
while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    $l = [ZW]::Snapshot()
    $s = [ZW]::Sample($l, $false)
    $samples++
    $stamp = (Get-Date -Format 'HH:mm:ss.fff')
    $line = "[t=" + [int]((Get-Date) - $t0).TotalMilliseconds + "ms " + $stamp + "] " + $s
    Write-Output $line
    if ($s -like '*OCCLUDED*') { $badSamples++; }
    # keep the log small: every 8th sample plus every state change plus every OCCLUDED sample
    $key = ($s -split '=>')[0]
    $key = ($key -replace 'hit=\S+', '')
    if ($s -like '*OCCLUDED*' -or $key -ne $last -or ($samples % 8) -eq 0 -or $Detail) {
        W $line
        if ($s -like '*OCCLUDED*' -and ((Get-Date) - $lastDump).TotalSeconds -ge 2) {
            W ([ZW]::Dump($l).TrimEnd()); $lastDump = Get-Date
        }
    }
    $last = $key
    Start-Sleep -Milliseconds $IntervalMs
}
W ("# done samples=$samples occluded=$badSamples")
Write-Output ("done: samples=$samples occludedSamples=$badSamples log=$out")
