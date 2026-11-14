import glob, os
pattern = r"C:\ProgramData\Windhawk\Engine\ModsWritable\mod-status\*_5076_*tray-icons*"
for f in glob.glob(pattern):
    raw = open(f, "rb").read()
    try:
        txt = raw.decode("utf-16")
    except Exception:
        txt = raw.decode("utf-8", "replace")
    print(os.path.basename(f))
    print(repr(txt[:300]))
