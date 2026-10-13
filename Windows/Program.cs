using System;
using System.Drawing;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace EmoteWheel;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        using var instance = new Mutex(true, "Local\\EmoteWheel.Desktop", out bool first);
        if (!first) { MessageBox.Show("EmoteWheel 已在运行，请双击任务栏右下角的托盘图标打开设置。", "EmoteWheel"); return 0; }
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        try
        {
            var model = new AppModel();
            if (args.Contains("--self-test", StringComparer.Ordinal)) return SelfTest(model);
            using var overlay = new OverlayController(model);
            var settings = new SettingsWindow(model, overlay);
            using var keyboard = new KeyboardController(model, overlay, Dispatcher.CurrentDispatcher);
            using var trayIcon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? (Icon)SystemIcons.Application.Clone();
            using var tray = new Forms.NotifyIcon { Text = "EmoteWheel · 表情轮盘", Icon = trayIcon, Visible = true };
            void ShowSettings() { settings.Show(); if (settings.WindowState == WindowState.Minimized) settings.WindowState = WindowState.Normal; settings.Activate(); }
            var menu = new Forms.ContextMenuStrip();
            menu.Items.Add("打开设置", null, (_, _) => app.Dispatcher.Invoke(ShowSettings));
            var enabled = new Forms.ToolStripMenuItem("启用快捷键") { Checked = model.Config.Enabled, CheckOnClick = true };
            enabled.Click += (_, _) => app.Dispatcher.Invoke(() => { model.Config.Enabled = enabled.Checked; model.Save(); });
            menu.Items.Add(enabled);
            menu.Items.Add("体验轮盘", null, (_, _) => app.Dispatcher.Invoke(() => overlay.Show(true)));
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("退出 EmoteWheel", null, (_, _) => app.Dispatcher.Invoke(() => { settings.Exiting = true; tray.Visible = false; app.Shutdown(); }));
            tray.ContextMenuStrip = menu; tray.DoubleClick += (_, _) => app.Dispatcher.Invoke(ShowSettings);
            model.Changed += () => enabled.Checked = model.Config.Enabled;
            app.Exit += (_, _) => { tray.Visible = false; settings.Exiting = true; };
            settings.Show();
            return app.Run();
        }
        catch (Exception ex)
        {
            string message = "EmoteWheel 启动失败：" + ex.Message + "\n请确认已完整解压应用，Resources 文件夹与 EmoteWheel.exe 位于同一目录。";
            if (args.Contains("--self-test", StringComparer.Ordinal)) { Console.Error.WriteLine(message); return 1; }
            MessageBox.Show(message, "EmoteWheel", MessageBoxButton.OK, MessageBoxImage.Error); return 1;
        }
    }

    // A Windows CI smoke check; does not install hooks, open windows, or change user settings.
    private static int SelfTest(AppModel model)
    {
        int failed = 0;
        foreach (var item in model.Catalog.Where(item => !item.Id.StartsWith("custom-", StringComparison.Ordinal)))
            if (model.Image(item.Id) == null) { Console.Error.WriteLine("无法加载表情：" + item.Id); failed++; }
        if (model.Catalog.Count < 8) failed++;
        Console.WriteLine($"Catalog: {model.Catalog.Count}; missing or invalid images: {failed}");
        return failed == 0 ? 0 : 1;
    }
}
