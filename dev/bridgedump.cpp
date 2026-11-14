// bridgedump.cpp - prints the tray bridge table (and optionally asks all apps to
// re-register, like the shell does after an explorer restart)
#include <windows.h>
#include <cstdio>

struct TrayBridgeEntry {
    unsigned long long hwnd;
    unsigned int uid;
    unsigned int cbMsg;
    unsigned int isGuid;
    unsigned int pid;
    GUID guid;
    wchar_t tip[128];
    wchar_t exe[MAX_PATH];
};
struct TrayBridgeShm {
    unsigned int magic;
    unsigned int version;
    unsigned int count;
    unsigned int capacity;
    unsigned long long updatedMs;
    TrayBridgeEntry entries[128];
};

int wmain(int argc, wchar_t** argv) {
    bool broadcast = (argc > 1 && _wcsicmp(argv[1], L"-b") == 0);
    if (broadcast) {
        UINT msg = RegisterWindowMessageW(L"TaskbarCreated");
        SendMessageTimeoutW(HWND_BROADCAST, msg, 0, 0, SMTO_ABORTIFHUNG | SMTO_NORMAL, 1500,
                            nullptr);
        EnumWindows(
            [](HWND h, LPARAM lp) -> BOOL {
                PostMessageW(h, (UINT)lp, 0, 0);
                return TRUE;
            },
            (LPARAM)msg);
        wprintf(L"broadcast TaskbarCreated (0x%X)\n", msg);
        Sleep(1500);
    }
    HANDLE m = OpenFileMappingW(FILE_MAP_READ, FALSE, L"Local\\DockTrayBridge_v1");
    if (!m) {
        wprintf(L"no mapping (err %lu)\n", GetLastError());
        return 1;
    }
    auto* s = (TrayBridgeShm*)MapViewOfFile(m, FILE_MAP_READ, 0, 0, sizeof(TrayBridgeShm));
    if (!s) {
        wprintf(L"map failed %lu\n", GetLastError());
        return 1;
    }
    wprintf(L"magic=%08X version=%u count=%u capacity=%u age=%llums\n", s->magic, s->version,
            s->count, s->capacity, GetTickCount64() - s->updatedMs);
    for (unsigned i = 0; i < s->count && i < 128; i++) {
        const auto& e = s->entries[i];
        wprintf(L"  [%2u] hwnd=%p uid=%u cb=0x%X pid=%u exe=%s tip='%s'\n", i, (void*)e.hwnd,
                e.uid, e.cbMsg, e.pid, e.exe, e.tip);
    }
    UnmapViewOfFile(s);
    CloseHandle(m);
    return 0;
}
