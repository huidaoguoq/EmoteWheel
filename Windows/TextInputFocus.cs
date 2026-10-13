using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Threading;

namespace EmoteWheel;

// UI Automation providers can be slow. Never call them inside a low-level hook or on the UI thread.
internal sealed class TextInputFocus : IDisposable
{
    private readonly BlockingCollection<(IntPtr Window, Action<bool> Result)> requests = new(1);
    private readonly Dispatcher dispatcher;
    public TextInputFocus(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        var worker = new Thread(Run) { IsBackground = true, Name = "EmoteWheel focus metadata" };
        worker.SetApartmentState(ApartmentState.MTA); worker.Start();
    }

    public void Check(IntPtr window, Action<bool> result)
    {
        if (!requests.TryAdd((window, result))) result(true);
    }

    private void Run()
    {
        foreach (var request in requests.GetConsumingEnumerable())
        {
            bool suppress = Suppress(request.Window);
            if (!dispatcher.HasShutdownStarted)
                dispatcher.BeginInvoke(() => request.Result(suppress));
        }
    }

    private static bool Suppress(IntPtr expectedWindow)
    {
        try
        {
            if (Native.GetForegroundWindow() != expectedWindow) return true;
            uint threadId = Native.GetWindowThreadProcessId(expectedWindow, out uint expectedProcess);
            var gui = new Native.GuiThreadInfo { Size = System.Runtime.InteropServices.Marshal.SizeOf<Native.GuiThreadInfo>() };
            if (Native.GetGUIThreadInfo(threadId, ref gui) && gui.Focus != IntPtr.Zero)
            {
                var name = new StringBuilder(256); Native.GetClassName(gui.Focus, name, name.Capacity);
                string className = name.ToString();
                if (className.Equals("Edit", StringComparison.OrdinalIgnoreCase) || className.StartsWith("RichEdit", StringComparison.OrdinalIgnoreCase)) return true;
            }

            var focused = AutomationElement.FocusedElement;
            if (focused == null || focused.Current.ProcessId != expectedProcess) return true;
            var deadline = Stopwatch.StartNew();
            bool recognized = false;
            for (int level = 0; focused != null && level < 16; level++)
            {
                if (deadline.ElapsedMilliseconds > 250) return true;
                var info = focused.Current;
                var type = info.ControlType;
                if (info.IsPassword || type == ControlType.Edit || type == ControlType.ComboBox) return true;
                if (focused.TryGetCurrentPattern(ValuePattern.Pattern, out var value) && !((ValuePattern)value).Current.IsReadOnly) return true;
                // The presence of TextPattern only means selectable text, not editable text.
                if (focused.TryGetCurrentPattern(TextPattern.Pattern, out var text))
                {
                    var readOnly = ((TextPattern)text).DocumentRange.GetAttributeValue(TextPattern.IsReadOnlyAttribute);
                    if (readOnly is bool isReadOnly && !isReadOnly) return true;
                }
                if (type == ControlType.Document) return false;
                if (type == ControlType.Window) return !recognized;
                recognized |= type == ControlType.Button || type == ControlType.Text || type == ControlType.Hyperlink ||
                    type == ControlType.Image || type == ControlType.List || type == ControlType.ListItem ||
                    type == ControlType.Tree || type == ControlType.TreeItem || type == ControlType.Tab ||
                    type == ControlType.TabItem || type == ControlType.CheckBox || type == ControlType.RadioButton ||
                    type == ControlType.Menu || type == ControlType.MenuItem || type == ControlType.ToolBar ||
                    type == ControlType.DataGrid || type == ControlType.DataItem || type == ControlType.Pane;
                focused = TreeWalker.ControlViewWalker.GetParent(focused);
            }
            return !recognized;
        }
        catch { return true; } // A missing/unresponsive provider must not turn ordinary typing into an emote.
    }

    public void Dispose() => requests.CompleteAdding();
}
