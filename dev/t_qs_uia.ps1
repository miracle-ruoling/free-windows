# Can UIA give us the quick settings panel's real content box?
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;

public class UA {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static void WinA() {
    keybd_event(0x5B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(90);
    keybd_event(0x41, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x41, 0, 2, UIntPtr.Zero); System.Threading.Thread.Sleep(90);
    keybd_event(0x5B, 0, 2, UIntPtr.Zero);
  }
  public static void Esc() {
    keybd_event(0x1B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x1B, 0, 2, UIntPtr.Zero);
  }
  public static string Dump() {
    IntPtr h = GetForegroundWindow();
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    RECT wr; GetWindowRect(h, out wr);
    string s = "fg=" + h.ToInt64() + " cls=" + b + " win=" + wr.Left + "," + wr.Top + " " + (wr.Right-wr.Left) + "x" + (wr.Bottom-wr.Top) + "\n";
    try {
      AutomationElement root = AutomationElement.FromHandle(h);
      if (root == null) return s + "no UIA element\n";
      AutomationElementCollection kids = root.FindAll(TreeScope.Children, Condition.TrueCondition);
      s += "children=" + kids.Count + "\n";
      int n = 0;
      foreach (AutomationElement k in kids) {
        if (n++ > 12) break;
        System.Windows.Rect r = k.Current.BoundingRectangle;
        s += string.Format("  [{0}] cls={1} name='{2}' rect={3:F0},{4:F0} {5:F0}x{6:F0}\n",
          k.Current.ControlType.ProgrammaticName, k.Current.ClassName, k.Current.Name,
          r.X, r.Y, r.Width, r.Height);
      }
    } catch (Exception e) { s += "UIA error: " + e.Message + "\n"; }
    return s;
  }
}
"@
[void][UA]::SetProcessDpiAwarenessContext([IntPtr](-4))
[UA]::Esc(); Start-Sleep -Milliseconds 700
[UA]::WinA(); Start-Sleep -Milliseconds 1500
Write-Output ([UA]::Dump())
[UA]::Esc(); Start-Sleep -Milliseconds 400
