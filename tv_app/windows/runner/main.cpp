#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(0, 0);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Cinematy TV", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  HWND hwnd = window.GetHandle();
  if (hwnd != nullptr) {
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(MONITORINFO);
    if (GetMonitorInfo(monitor, &monitor_info)) {
      SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
      LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
      ex_style &= ~(WS_EX_CLIENTEDGE | WS_EX_WINDOWEDGE | WS_EX_DLGMODALFRAME);
      SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

      const RECT& r = monitor_info.rcMonitor;
      SetWindowPos(hwnd, HWND_TOP,
                   r.left, r.top,
                   r.right - r.left,
                   r.bottom - r.top,
                   SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOOWNERZORDER);
      ShowWindow(hwnd, SW_SHOW);
      UpdateWindow(hwnd);
      SetForegroundWindow(hwnd);
      SetFocus(hwnd);
    }
  }

  MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
