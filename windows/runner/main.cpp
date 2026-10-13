#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// The window title, which is also how a second launch finds the first one.
constexpr wchar_t kWindowTitle[] = L"mostro";

// `mostro:` order links (docs/DEEP_LINKS.md). A debug build takes no part:
// handing over to an open Mostro would end `flutter run` against a release
// build, and claiming the scheme would point the user's links at the debug
// build. It still reads a link it is started with.
#ifndef _DEBUG

// Hands a `mostro:` link on the command line to the window already open, and
// brings that window forward: the link opens there, not in a second instance
// (app_links). Without a link it only brings the window forward.
bool SendAppLinkToInstance() {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
  if (!hwnd) {
    return false;
  }
  SendAppLink(hwnd);

  WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
  ::GetWindowPlacement(hwnd, &place);
  switch (place.showCmd) {
    case SW_SHOWMAXIMIZED:
      ::ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ::ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ::ShowWindow(hwnd, SW_NORMAL);
      break;
  }
  ::SetForegroundWindow(hwnd);
  return true;
}

void SetUserClassValue(const wchar_t* subkey, const wchar_t* name,
                       const std::wstring& value) {
  ::RegSetKeyValueW(HKEY_CURRENT_USER, subkey, name, REG_SZ, value.c_str(),
                    static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
}

// Makes this executable the handler of `mostro:` links for the current user.
// The release is a zip with no installer, so it does so at every start: a
// moved folder moves the handler with it.
void RegisterOrderLinkScheme() {
  constexpr DWORD kPathCapacity = MAX_PATH;
  wchar_t path[kPathCapacity];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, kPathCapacity);
  if (length == 0 || length == kPathCapacity) {
    return;
  }
  const wchar_t* scheme = L"Software\\Classes\\mostro";
  SetUserClassValue(scheme, nullptr, L"URL:Mostro order link");
  SetUserClassValue(scheme, L"URL Protocol", L"");
  SetUserClassValue(L"Software\\Classes\\mostro\\shell\\open\\command",
                    nullptr, L"\"" + std::wstring(path) + L"\" \"%1\"");
}

#endif  // _DEBUG

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
#ifndef _DEBUG
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }
  RegisterOrderLinkScheme();
#endif

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
