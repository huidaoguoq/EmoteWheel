using System;
using System.Drawing;
using System.Buffers.Binary;
using System.IO;
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
        if (args.Contains("--self-test", StringComparer.Ordinal))
        {
            try { return SelfTest(new AppModel(loadSettings: false)); }
            catch (Exception ex) { Console.Error.WriteLine("Self-test exception: " + ex); return 1; }
        }
        using var instance = new Mutex(true, "Local\\EmoteWheel.Desktop", out bool first);
        if (!first) { MessageBox.Show("EmoteWheel 已在运行，请双击任务栏右下角的托盘图标打开设置。", "EmoteWheel"); return 0; }
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        try
        {
            var model = new AppModel();
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
            app.Exit += (_, _) => { model.CancelDownload(); tray.Visible = false; settings.Exiting = true; };
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
        void Check(string name, Func<bool> condition)
        {
            try
            {
                if (condition()) { Console.WriteLine("PASS: " + name); return; }
                Console.Error.WriteLine("FAIL: " + name);
            }
            catch (Exception ex) { Console.Error.WriteLine("FAIL: " + name + " threw " + ex); }
            failed++;
        }
        Check($"Catalog count is 2400 (actual {model.Catalog.Count})", () => model.Catalog.Count == 2400);
        Check("Catalog has 2400 unique IDs", () => model.Catalog.Select(item => item.Id).Distinct().Count() == 2400);
        var sources = EmoteDownloads.Sources();
        Check($"Download source count is 2400 (actual {sources.Count})", () => sources.Count == 2400);
        Check("Download sources have 2400 unique IDs", () => sources.Select(item => item.Id).Distinct().Count() == 2400);
        Check("Every download source ID exists in the catalog", () => sources.All(item => model.Find(item.Id.ToString(System.Globalization.CultureInfo.InvariantCulture)) != null));
        string folder = Path.Combine(AppContext.BaseDirectory, "Resources", "emotes");
        Check("Published Resources/emotes contains exactly 8 PNG files", () => Directory.GetFiles(folder, "*.png").Length == 8);
        foreach (string id in Configuration.DefaultSlots)
            Check("Bundled PNG decodes: " + id, () => EmoteDownloads.ValidImage(Path.Combine(folder, id + ".png")));
        string invalid = Path.GetTempFileName();
        try
        {
            File.WriteAllText(invalid, "<html>Server error</html>");
            Check("HTML error body is rejected", () => !EmoteDownloads.ValidImage(invalid));
            File.WriteAllBytes(invalid, new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
            Check("PNG signature without image data is rejected", () => !EmoteDownloads.ValidImage(invalid));
            byte[] corrupted = File.ReadAllBytes(Path.Combine(folder, Configuration.DefaultSlots[0] + ".png"));
            bool foundPixels = false;
            for (int offset = 8; offset + 12 <= corrupted.Length;)
            {
                int length = BinaryPrimitives.ReadInt32BigEndian(corrupted.AsSpan(offset, 4));
                if (length < 0 || length > corrupted.Length - offset - 12) break;
                if (length > 0 && corrupted.AsSpan(offset + 4, 4).SequenceEqual("IDAT"u8))
                {
                    corrupted[offset + 8] ^= 0xff; // Keep a valid PNG header but break the compressed pixel data.
                    foundPixels = true;
                    break;
                }
                offset += length + 12;
            }
            File.WriteAllBytes(invalid, corrupted);
            Check("Corrupt PNG fixture contains an IDAT chunk", () => foundPixels);
            if (foundPixels) Check("PNG with corrupted IDAT bytes is rejected", () => !EmoteDownloads.ValidImage(invalid));
        }
        finally { File.Delete(invalid); }
        Console.WriteLine($"Catalog: {model.Catalog.Count}; starter images: 8; failures: {failed}");
        return failed == 0 ? 0 : 1;
    }
}
