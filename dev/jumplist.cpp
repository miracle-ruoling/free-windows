// jumplist.cpp - read what the shell keeps for taskbar jump lists, so the dock can show
// a "close to the native taskbar" context menu on strip icons.
//
// Both file kinds are OLE compound documents:
//   %APPDATA%\Microsoft\Windows\Recent\AutomaticDestinations\*.automaticDestinations-ms
//       recent/frequent items ("最近打开"), plus a DestList stream with titles/order
//   %APPDATA%\Microsoft\Windows\Recent\CustomDestinations\*.customDestinations-ms
//       the app's own "tasks" (VSCode's "New Window", 7-Zip's "Compress"...)
// Each numbered stream is a shell link; the display name lives in PKEY_Title.
//
// Usage:
//   jumplist.exe                 -> dump every destination file
//   jumplist.exe -exe <path>     -> only links whose target is that exe
//   jumplist.exe -file <path>    -> one file
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <propkey.h>
#include <propvarutil.h>
#include <cstdio>
#include <string>
#include <vector>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "propsys.lib")

static void Print(const wchar_t* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vwprintf(fmt, ap);
    va_end(ap);
}

static std::wstring PropTitle(IShellLinkW* lnk) {
    std::wstring out;
    IPropertyStore* ps = nullptr;
    if (SUCCEEDED(lnk->QueryInterface(IID_IPropertyStore, (void**)&ps))) {
        PROPVARIANT v;
        PropVariantInit(&v);
        if (SUCCEEDED(ps->GetValue(PKEY_Title, &v)) && v.vt == VT_LPWSTR && v.pwszVal)
            out = v.pwszVal;
        else if (v.vt == VT_BSTR && v.bstrVal)
            out = v.bstrVal;
        PropVariantClear(&v);
        ps->Release();
    }
    return out;
}


// .customDestinations-ms is not an OLE compound file: it is a flat sequence of shell
// link structures (with a small header), so scan for the link header magic and load
// each hit as an IShellLink from memory.
static void DumpCustomFile(const std::wstring& path, const std::wstring& onlyExe) {
    HANDLE f = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                           OPEN_EXISTING, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE) {
        Print(L"[%s] cannot open raw (err=%lu)\n", PathFindFileNameW(path.c_str()), GetLastError());
        return;
    }
    LARGE_INTEGER size{};
    GetFileSizeEx(f, &size);
    std::vector<BYTE> buf((size_t)size.QuadPart);
    DWORD read = 0;
    ReadFile(f, buf.data(), (DWORD)buf.size(), &read, nullptr);
    CloseHandle(f);

    static const BYTE magic[] = {0x4C, 0x00, 0x00, 0x00, 0x01, 0x14, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46};
    std::wstring lines;
    int shown = 0;
    for (size_t i = 0; i + sizeof(magic) < buf.size(); i++) {
        if (memcmp(buf.data() + i, magic, sizeof(magic)) != 0) continue;
        IStream* s = SHCreateMemStream(buf.data() + i, (UINT)(buf.size() - i));
        if (!s) continue;
        IShellLinkW* lnk = nullptr;
        if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                       IID_IShellLinkW, (void**)&lnk))) {
            IPersistStream* ps = nullptr;
            if (SUCCEEDED(lnk->QueryInterface(IID_IPersistStream, (void**)&ps))) {
                if (SUCCEEDED(ps->Load(s))) {
                    wchar_t target[MAX_PATH]{};
                    WIN32_FIND_DATAW fd{};
                    lnk->GetPath(target, MAX_PATH, &fd, SLGP_RAWPATH);
                    wchar_t args[1024]{};
                    lnk->GetArguments(args, 1024);
                    std::wstring title = PropTitle(lnk);
                    bool match = onlyExe.empty() ||
                                 (target[0] && _wcsicmp(target, onlyExe.c_str()) == 0);
                    if (match) {
                        lines += L"    offset=";
                        wchar_t nb[32]{};
                        _snwprintf_s(nb, _countof(nb), _TRUNCATE, L"%zu", i);
                        lines += nb;
                        lines += L" title='";
                        lines += title;
                        lines += L"' target='";
                        lines += target;
                        lines += L"' args='";
                        lines += args;
                        lines += L"'\n";
                        shown++;
                    }
                }
                ps->Release();
            }
            lnk->Release();
        }
        s->Release();
    }
    if (shown > 0) {
        Print(L"[%s] %d task link(s)\n", PathFindFileNameW(path.c_str()), shown);
        wprintf(L"%s", lines.c_str());
    }
}

static void DumpFile(const std::wstring& path, const std::wstring& onlyExe) {
    // The shell keeps these files open; StgOpenStorageEx then fails with
    // STG_E_SHAREVIOLATION (0x800300FF), so work on a copy instead of interfering.
    wchar_t tmpFile[MAX_PATH]{};
    GetModuleFileNameW(nullptr, tmpFile, MAX_PATH);
    PathRemoveFileSpecW(tmpFile);
    PathAppendW(tmpFile, L"jl_tmp.stg");
    DeleteFileW(tmpFile);
    if (!CopyFileW(path.c_str(), tmpFile, FALSE)) {
        Print(L"[%s] cannot copy (err=%lu)\n", PathFindFileNameW(path.c_str()), GetLastError());
        return;
    }
    IStorage* st = nullptr;
    HRESULT hr = StgOpenStorageEx(tmpFile, STGM_READ | STGM_SHARE_EXCLUSIVE, STGFMT_STORAGE, 0,
                                  nullptr, nullptr, IID_IStorage, (void**)&st);
    if (FAILED(hr) || !st) {
        Print(L"[%s] cannot open (hr=0x%08X)\n", PathFindFileNameW(path.c_str()), (unsigned)hr);
        return;
    }
    IEnumSTATSTG* en = nullptr;
    int shown = 0;
    std::wstring lines;
    if (SUCCEEDED(st->EnumElements(0, nullptr, 0, &en)) && en) {
        STATSTG ss{};
        while (en->Next(1, &ss, nullptr) == S_OK) {
            if (ss.type == STGTY_STREAM && ss.pwcsName) {
                IStream* s = nullptr;
                if (SUCCEEDED(st->OpenStream(ss.pwcsName, nullptr, STGM_READ | STGM_SHARE_EXCLUSIVE, 0,
                                             &s)) &&
                    s) {
                    IShellLinkW* lnk = nullptr;
                    if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                                   IID_IShellLinkW, (void**)&lnk))) {
                        IPersistStream* ps = nullptr;
                        if (SUCCEEDED(lnk->QueryInterface(IID_IPersistStream, (void**)&ps))) {
                            if (SUCCEEDED(ps->Load(s))) {
                                wchar_t target[MAX_PATH]{};
                                WIN32_FIND_DATAW fd{};
                                lnk->GetPath(target, MAX_PATH, &fd, SLGP_RAWPATH);
                                wchar_t args[1024]{};
                                lnk->GetArguments(args, 1024);
                                std::wstring title = PropTitle(lnk);
                                bool match = onlyExe.empty() ||
                                             (target[0] &&
                                              _wcsicmp(target, onlyExe.c_str()) == 0);
                                if (match) {
                                    lines += L"    stream=";
                                    lines += ss.pwcsName;
                                    lines += L" title='";
                                    lines += title;
                                    lines += L"' target='";
                                    lines += target;
                                    lines += L"' args='";
                                    lines += args;
                                    lines += L"'\n";
                                    shown++;
                                }
                            }
                            ps->Release();
                        }
                        lnk->Release();
                    }
                    s->Release();
                }
                CoTaskMemFree(ss.pwcsName);
                ss.pwcsName = nullptr;
            }
        }
        en->Release();
    }
    st->Release();
    DeleteFileW(tmpFile);
    if (shown > 0) {
        Print(L"[%s] %d link(s)\n", PathFindFileNameW(path.c_str()), shown);
        wprintf(L"%s", lines.c_str());
    }
}

int wmain(int argc, wchar_t** argv) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    std::wstring onlyExe, onlyFile;
    for (int i = 1; i < argc; i++) {
        if (!_wcsicmp(argv[i], L"-exe") && i + 1 < argc) onlyExe = argv[++i];
        else if (!_wcsicmp(argv[i], L"-file") && i + 1 < argc) onlyFile = argv[++i];
    }
    if (!onlyFile.empty()) {
        DumpFile(onlyFile, onlyExe);
        CoUninitialize();
        return 0;
    }
    wchar_t appdata[MAX_PATH]{};
    SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, appdata);
    const wchar_t* dirs[2] = {L"\\Microsoft\\Windows\\Recent\\AutomaticDestinations",
                              L"\\Microsoft\\Windows\\Recent\\CustomDestinations"};
    const wchar_t* pats[2] = {L"\\*.automaticDestinations-ms", L"\\*.customDestinations-ms"};
    for (int d = 0; d < 2; d++) {
        std::wstring dir = std::wstring(appdata) + dirs[d];
        std::wstring pat = dir + pats[d];
        Print(L"=== %s\n", dir.c_str());
        WIN32_FIND_DATAW fd{};
        HANDLE h = FindFirstFileW(pat.c_str(), &fd);
        if (h == INVALID_HANDLE_VALUE) {
            Print(L"    (none)\n");
            continue;
        }
        do {
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
            if (d == 1) DumpCustomFile(dir + L"\\" + fd.cFileName, onlyExe);
            else DumpFile(dir + L"\\" + fd.cFileName, onlyExe);
        } while (FindNextFileW(h, &fd));
        FindClose(h);
    }
    CoUninitialize();
    return 0;
}
