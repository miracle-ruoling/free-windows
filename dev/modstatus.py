import glob, os
files = glob.glob(r"C:\ProgramData\Windhawk\Engine\ModsWritable\mod-status\*tray-icons*")
print(len(files), "status files")
for f in files[-2:]:
    txt = open(f, "rb").read().decode("utf-16", "replace")
    parts = [p.strip() for p in txt.split("|")]
    print("---", os.path.basename(f)[:50], "items:", len(parts))
    for i in range(0, len(parts) - 1, 2):
        name = parts[i].lower()
        if any(k in name for k in ("wallpaper", "lenovo", "windhawk", "radmin", "vscodium")):
            print("   ", parts[i], "->", parts[i + 1])
