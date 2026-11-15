# Render a sheet of Segoe Fluent Icons / Segoe MDL2 Assets glyphs with their codepoints, so
# the tray-style icons (wifi / volume / battery and their level variants) can be picked by
# eye instead of guessed.
param([string]$Out = "glyph_sheet.png")
Add-Type -AssemblyName System.Drawing
Add-Type -Language CSharp @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;

public class GlyphSheet {
  public static string Render(string outPath, int size, int[] codes) {
    int cols = 8;
    int cell = size + 46;
    int rows = (codes.Length + cols - 1) / cols;
    using (Bitmap bmp = new Bitmap(cols * cell, rows * cell)) {
      using (Graphics g = Graphics.FromImage(bmp)) {
        g.Clear(Color.FromArgb(24, 24, 24));
        g.TextRenderingHint = TextRenderingHint.AntiAlias;
        Font iconFont = null;
        string used = "?";
        foreach (string name in new string[] { "Segoe Fluent Icons", "Segoe MDL2 Assets" }) {
          try {
            Font f = new Font(name, size, GraphicsUnit.Pixel);
            if (f.Name.IndexOf("Segoe", StringComparison.OrdinalIgnoreCase) >= 0) { iconFont = f; used = f.Name; break; }
          } catch { }
        }
        if (iconFont == null) return "no icon font";
        Font label = new Font("Consolas", 13, GraphicsUnit.Pixel);
        SolidBrush white = new SolidBrush(Color.White);
        SolidBrush yellow = new SolidBrush(Color.FromArgb(255, 214, 96));
        for (int i = 0; i < codes.Length; i++) {
          int cx = (i % cols) * cell;
          int cy = (i / cols) * cell;
          string ch = char.ConvertFromUtf32(codes[i]);
          g.DrawString(ch, iconFont, yellow, cx + 8, cy + 4);
          g.DrawString(codes[i].ToString("X4"), label, white, cx + 8, cy + size + 14);
        }
        bmp.Save(outPath, ImageFormat.Png);
        return used + " -> " + outPath;
      }
    }
  }
}
"@
$codes = @()
$codes += 0xE700..0xE70F      # wifi / signal
$codes += 0xE720..0xE72F
$codes += 0xE740..0xE74F      # mute?
$codes += 0xE990..0xE99F      # volume levels
$codes += 0xE838..0xE847      # ethernet / battery area
$codes += 0xE848..0xE85F
$codes += 0xEBA0..0xEBAF      # battery charging area
$path = Join-Path $PSScriptRoot $Out
Write-Output ([GlyphSheet]::Render($path, 44, [int[]]$codes))
Write-Output ("codes: " + $codes.Count)
