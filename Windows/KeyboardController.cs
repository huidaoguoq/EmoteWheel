using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Threading;

namespace EmoteWheel;

internal sealed class KeyboardController : IDisposable
{
    private readonly AppModel model;
    private readonly OverlayController overlay;
    private readonly Dispatcher dispatcher;
    private readonly TextInputFocus focus;
    private readonly Native.HookProc callback;
    private readonly HashSet<int> held = new();
    private readonly DispatcherTimer guard;
    private IntPtr hook;
    private IntPtr startingWindow;
    private int generation;
    private bool pending;

    public KeyboardController(AppModel model, OverlayController overlay, Dispatcher dispatcher)
    {
        this.model = model; this.overlay = overlay; this.dispatcher = dispatcher;
        focus = new TextInputFocus(dispatcher); callback = Hook;
        hook = Native.SetWindowsHookEx(13, callback, Native.GetModuleHandle(null), 0);
        if (hook == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "无法启动全局快捷键监听");
        guard = new DispatcherTimer(TimeSpan.FromMilliseconds(16), DispatcherPriority.Input, (_, _) => Guard(), dispatcher);
        model.Changed += SettingsChanged;
    }

    private IntPtr Hook(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            int kind = (int)message;
            if (kind is Native.WmKeyDown or Native.WmSysKeyDown or Native.WmKeyUp or Native.WmSysKeyUp)
            {
                var item = Marshal.PtrToStructure<Native.KeyData>(data);
                if ((item.Flags & 0x10) == 0) // Ignore injected events; always pass original events through.
                {
                    int key = (int)item.VirtualKey;
                    bool down = kind is Native.WmKeyDown or Native.WmSysKeyDown;
                    IntPtr foreground = Native.GetForegroundWindow();
                    var modifiers = Native.Modifiers();
                    dispatcher.BeginInvoke(() => Handle(key, down, foreground, modifiers));
                }
            }
        }
        return Native.CallNextHookEx(hook, code, message, data);
    }

    private void Handle(int key, bool down, IntPtr foreground, HotkeyModifiers modifiers)
    {
        if (!down)
        {
            held.Remove(key);
            if (key != model.Config.VirtualKey) return;
            pending = false;
            int token = ++generation;
            if (!overlay.Active || overlay.IsPreview) return;
            if (foreground != startingWindow || modifiers != model.Config.Modifiers) { overlay.Cancel(); return; }
            // Freeze the selected slot, then verify focus again before displaying it.
            var selection = overlay.TakeSelection();
            if (selection == null) return;
            focus.Check(foreground, suppress =>
            {
                if (!suppress && token == generation && Native.GetForegroundWindow() == foreground)
                    overlay.Display(selection.Value.Id, selection.Value.X, selection.Value.Y);
            });
            return;
        }
        if (!held.Add(key)) return;
        if (key == 0x1B)
        {
            if (model.RecordingKey) model.SetRecording(false);
            Cancel(); return;
        }
        if (model.RecordingKey)
        {
            if (Configuration.IsModifier(key)) return;
            model.Config.VirtualKey = key; model.Config.Modifiers = modifiers;
            model.Config.KeyLabel = KeyInterop.KeyFromVirtualKey(key).ToString();
            model.RecordingKey = false; model.Save(); return;
        }
        if (key == 0x20 && key != model.Config.VirtualKey) { Cancel(); return; }
        if (!model.Config.Enabled || model.ModalOpen || key != model.Config.VirtualKey || modifiers != model.Config.Modifiers) return;
        if (overlay.IsPreview) { Cancel(); return; }
        startingWindow = foreground; pending = true;
        int queryGeneration = ++generation;
        focus.Check(foreground, suppress =>
        {
            if (!pending || queryGeneration != generation) return;
            pending = false;
            if (!suppress && Native.Down(key) && Native.Modifiers() == model.Config.Modifiers &&
                Native.GetForegroundWindow() == foreground && !model.ModalOpen && model.Config.Enabled && !model.RecordingKey)
                overlay.Show(false);
        });
    }

    private void Guard()
    {
        if (!(pending || overlay.Active)) return;
        if (Native.Down(0x02) || Native.Down(0x1B)) { Cancel(); return; }
        if (overlay.IsPreview && Native.GetForegroundWindow() != overlay.ForegroundAtShow) { Cancel(); return; }
        if (!overlay.IsPreview && Native.Modifiers() != model.Config.Modifiers) { Cancel(); return; }
        if (!overlay.IsPreview && Native.GetForegroundWindow() != startingWindow) Cancel();
    }

    private void SettingsChanged() => Cancel();
    public void Cancel() { ++generation; pending = false; overlay.Cancel(); }
    public void Dispose()
    {
        guard.Stop(); model.Changed -= SettingsChanged; focus.Dispose();
        if (hook != IntPtr.Zero) { Native.UnhookWindowsHookEx(hook); hook = IntPtr.Zero; }
    }
}
