// aumid.cpp - print each window's exe + AppUserModelID, and compute the jump list
// destination-file hash variants for a given AUMID, so we can find out which file
// belongs to which app (instead of guessing from the target exe).
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propsys.h>
#include <shlwapi.h>
#include <string>
#include <vector>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "propsys.lib")

static std::wstring WindowAumid(HWND h) {
    std::wstring out;
    IPropertyStore* ps = nullptr;
    if (SUCCEEDED(SHGetPropertyStoreForWindow(h, IID_IPropertyStore, (void**)&ps))) {
        PROPVARIANT v;
        PropVariantInit(&v);
        if (SUCCEEDED(ps->GetValue(PKEY_AppUserModel_ID, &v))) {
            if (v.vt == VT_LPWSTR && v.pwszVal) out = v.pwszVal;
            else if (v.vt == VT_BSTR && v.bstrVal) out = v.bstrVal;
        }
        PropVariantClear(&v);
        ps->Release();
    }
    return out;
}

static std::wstring WindowExe(HWND h) {
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (!pid) return L"";
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p) return L"";
    wchar_t buf[MAX_PATH]{};
    DWORD n = MAX_PATH;
    std::wstring out;
    if (QueryFullProcessImageNameW(p, 0, buf, &n)) out = buf;
    CloseHandle(p);
    return out;
}

// CRC64 candidates (init 0, no final xor), both bit orders, both input encodings.
static ULONGLONG Crc64Poly(ULONGLONG poly, bool reflected, const BYTE* d, size_t n) {
    ULONGLONG crc = 0;
    if (!reflected) {
        for (size_t i = 0; i < n; i++) {
            crc ^= (ULONGLONG)d[i] << 56;
            for (int b = 0; b < 8; b++)
                crc = (crc & 0x8000000000000000ULL) ? (crc << 1) ^ poly : (crc << 1);
        }
    } else {
        for (size_t i = 0; i < n; i++) {
            crc ^= d[i];
            for (int b = 0; b < 8; b++)
                crc = (crc & 1) ? (crc >> 1) ^ poly : (crc >> 1);
        }
    }
    return crc;
}

static void HashVariants(const std::wstring& s) {
    std::wstring low = s;
    for (auto& c : low) c = towlower(c);
    struct Variant {
        const wchar_t* name;
        ULONGLONG poly;
        bool refl;
        bool utf16;
        bool lower;
    } vs[] = {
        {L"poly04C11DB7 utf16 lower", 0x04C11DB7ULL, false, true, true},
        {L"poly04C11DB7 utf16 as-is", 0x04C11DB7ULL, false, true, false},
        {L"poly04C11DB7 ansi  lower", 0x04C11DB7ULL, false, false, true},
        {L"poly42F0E1EBA9EA3693 utf16 lower", 0x42F0E1EBA9EA3693ULL, false, true, true},
        {L"polyC96C5795D7870F42 utf16 lower", 0xC96C5795D7870F42ULL, true, true, true},
        {L"poly04C11DB7 refl utf16 lower", 0xEDB88320ULL, true, true, true},
    };
    for (const auto& v : vs) {
        const std::wstring& src = v.lower ? low : s;
        if (v.utf16) {
            ULONGLONG h = Crc64Poly(v.poly, v.refl, (const BYTE*)src.c_str(),
                                    src.size() * sizeof(wchar_t));
            wprintf(L"  %-40s %016llx\n", v.name, h);
        } else {
            char buf[512]{};
            WideCharToMultiByte(CP_ACP, 0, src.c_str(), -1, buf, sizeof(buf) - 1, nullptr, nullptr);
            ULONGLONG h = Crc64Poly(v.poly, v.refl, (const BYTE*)buf, strlen(buf));
            wprintf(L"  %-40s %016llx\n", v.name, h);
        }
    }
}

int wmain(int argc, wchar_t** argv) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (argc >= 3 && !_wcsicmp(argv[1], L"-hash")) {
        wprintf(L"AUMID '%s'\n", argv[2]);
        HashVariants(argv[2]);
        CoUninitialize();
        return 0;
    }
    struct Ctx {
        int n;
    } ctx{0};
    EnumWindows(
        [](HWND h, LPARAM lp) -> BOOL {
            if (!IsWindowVisible(h)) return TRUE;
            int len = GetWindowTextLengthW(h);
            if (len <= 0) return TRUE;
            auto* c = reinterpret_cast<Ctx*>(lp);
            std::wstring aumid = WindowAumid(h);
            std::wstring exe = WindowExe(h);
            if (aumid.empty() && exe.empty()) return TRUE;
            wchar_t title[160]{};
            GetWindowTextW(h, title, 160);
            wprintf(L"%s\n    exe=%s\n    aumid='%s'\n", title, exe.c_str(), aumid.c_str());
            c->n++;
            return TRUE;
        },
        (LPARAM)&ctx);
    CoUninitialize();
    return 0;
}
