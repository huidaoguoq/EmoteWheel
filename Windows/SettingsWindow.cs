using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace EmoteWheel;

internal sealed class SettingsWindow : Window
{
    private readonly AppModel model;
    private readonly OverlayController overlay;
    private readonly TextBlock shortcut = new(), status = new(), count = new(), pageLabel = new();
    private readonly Button record = new(), download = new(), cancelDownload = new();
    private readonly TextBlock downloadStatus = new();
    private readonly ProgressBar downloadProgress = new() { Height = 4, Margin = new Thickness(0, 8, 0, 0) };
    private readonly CheckBox enabled = new() { Content = "启用全局快捷键", VerticalAlignment = VerticalAlignment.Center };
    private readonly UniformGrid slots = new() { Columns = 8 };
    private readonly UniformGrid library = new() { Columns = 8 };
    private readonly TextBox search = new();
    private readonly Slider wheelScale = new() { Minimum = .8, Maximum = 1.3, Width = 160, TickFrequency = .1, IsSnapToTickEnabled = true };
    private readonly Slider duration = new() { Minimum = 1, Maximum = 5, Width = 160, TickFrequency = .1 };
    private readonly TextBlock scaleLabel = new(), durationLabel = new();
    private readonly Button previous = new(), next = new();
    private readonly ScrollViewer libraryScroll = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    private const int PageSize = 64;
    private int page;
    private bool refreshing;
    private List<Emote> filtered = new();
    public bool Exiting { get; set; }
    private static readonly Brush BackgroundBrush = Color("#08141E"), Card = Color("#102432"), Gold = Color("#C7A35E"), Muted = Color("#8FA3B2");
    private static Brush Color(string hex) => (Brush)new BrushConverter().ConvertFromString(hex)!;

    public SettingsWindow(AppModel model, OverlayController overlay)
    {
        this.model = model; this.overlay = overlay;
        Title = "EmoteWheel · 表情轮盘"; Width = 1080; Height = 850; MinWidth = 850; MinHeight = 680;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = BackgroundBrush; Foreground = Brushes.WhiteSmoke;
        FontFamily = new FontFamily("Microsoft YaHei UI"); FontSize = 13;
        Resources[typeof(Button)] = ButtonStyle();
        var layout = new Grid { Margin = new Thickness(30, 23, 30, 18) };
        foreach (var height in new[] { GridLength.Auto, GridLength.Auto, GridLength.Auto, GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto })
            layout.RowDefinitions.Add(new RowDefinition { Height = height });
        Content = layout;

        var header = new DockPanel { Margin = new Thickness(0, 0, 0, 20) };
        var brand = new StackPanel();
        brand.Children.Add(new TextBlock { Text = "EMOTE WHEEL", Foreground = Gold, FontSize = 12, FontWeight = FontWeights.Bold });
        brand.Children.Add(new TextBlock { Text = "让表情，说出你的心情。", FontSize = 27, Margin = new Thickness(0, 6, 0, 6), FontWeight = FontWeights.SemiBold });
        brand.Children.Add(new TextBlock { Text = "按住快捷键 → 移动鼠标选择 → 松开，在桌面展示表情", Foreground = Muted });
        header.Children.Add(brand); Add(layout, header, 0);

        var controls = new WrapPanel { Margin = new Thickness(0, 0, 0, 16), VerticalAlignment = VerticalAlignment.Center };
        enabled.Margin = new Thickness(0, 0, 20, 0);
        enabled.Click += (_, _) => { if (!refreshing) { model.Config.Enabled = enabled.IsChecked == true; model.Save(); } };
        controls.Children.Add(enabled);
        shortcut.FontSize = 18; shortcut.Foreground = Gold; shortcut.VerticalAlignment = VerticalAlignment.Center; shortcut.Margin = new Thickness(0, 0, 14, 0);
        controls.Children.Add(shortcut);
        record.Click += (_, _) => { model.SetRecording(!model.RecordingKey); if (model.RecordingKey) Focus(); };
        controls.Children.Add(record);
        controls.Children.Add(Button("体验轮盘", () => { model.SetRecording(false); overlay.Show(true); }));
        controls.Children.Add(Button("导入图片", Import));
        controls.Children.Add(Button("恢复默认", () => { model.Reset(); RefreshLibrary(); }));
        Add(layout, controls, 1);

        var setup = new StackPanel { Margin = new Thickness(0, 0, 0, 16) };
        setup.Children.Add(new TextBlock { Text = "轮盘装配  /  先选择一个槽位，再点击下方表情", Foreground = Muted, Margin = new Thickness(0, 0, 0, 8) });
        setup.Children.Add(slots);
        var sliders = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };
        sliders.Children.Add(new TextBlock { Text = "轮盘大小", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) });
        sliders.Children.Add(wheelScale); scaleLabel.Width = 60; scaleLabel.Margin = new Thickness(8, 0, 16, 0); sliders.Children.Add(scaleLabel);
        sliders.Children.Add(new TextBlock { Text = "展示时长", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) });
        sliders.Children.Add(duration); durationLabel.Margin = new Thickness(8, 0, 0, 0); sliders.Children.Add(durationLabel);
        wheelScale.ValueChanged += (_, _) => { if (!refreshing) { model.Config.WheelScale = wheelScale.Value; model.Save(); } };
        duration.ValueChanged += (_, _) => { if (!refreshing) { model.Config.DisplayDuration = duration.Value; model.Save(); } };
        setup.Children.Add(sliders); Add(layout, setup, 2);

        var searchRow = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
        count.Foreground = Muted; count.VerticalAlignment = VerticalAlignment.Center; DockPanel.SetDock(count, Dock.Right); searchRow.Children.Add(count);
        search.Width = 330; search.HorizontalAlignment = HorizontalAlignment.Left; search.FontSize = 14; search.Padding = new Thickness(10, 7, 10, 7);
        search.Background = Card; search.Foreground = Brushes.WhiteSmoke; search.BorderBrush = Color("#294252");
        search.ToolTip = "搜索中文名称、英文名称、别名或 ID，如：弱爆 / 流汗";
        System.Windows.Automation.AutomationProperties.SetName(search, "搜索名称、别名或 ID");
        search.TextChanged += (_, _) => { page = 0; RefreshLibrary(); };
        var searchGroup = new StackPanel { Orientation = Orientation.Horizontal };
        searchGroup.Children.Add(new TextBlock { Text = "搜索表情", VerticalAlignment = VerticalAlignment.Center, Foreground = Gold, Margin = new Thickness(0, 0, 12, 0) });
        searchGroup.Children.Add(search); searchGroup.Children.Add(Button("清空", () => search.Clear()));
        searchRow.Children.Add(searchGroup); Add(layout, searchRow, 3);

        var downloads = new StackPanel { Margin = new Thickness(0, 0, 0, 12) };
        var downloadRow = new DockPanel();
        var downloadButtons = new StackPanel { Orientation = Orientation.Horizontal };
        DockPanel.SetDock(downloadButtons, Dock.Right);
        download.Click += async (_, _) => await model.DownloadAll();
        cancelDownload.Content = "取消"; cancelDownload.Click += (_, _) => model.CancelDownload();
        downloadButtons.Children.Add(download); downloadButtons.Children.Add(cancelDownload);
        downloadRow.Children.Add(downloadButtons);
        downloadStatus.Foreground = Muted; downloadStatus.VerticalAlignment = VerticalAlignment.Center;
        downloadStatus.TextWrapping = TextWrapping.Wrap; downloadRow.Children.Add(downloadStatus);
        downloads.Children.Add(downloadRow); downloads.Children.Add(downloadProgress); Add(layout, downloads, 4);

        libraryScroll.Content = library; Add(layout, libraryScroll, 5);
        var footer = new DockPanel { Margin = new Thickness(0, 10, 0, 0) };
        var pagination = new StackPanel { Orientation = Orientation.Horizontal }; DockPanel.SetDock(pagination, Dock.Right);
        previous.Content = "上一页"; previous.Click += (_, _) => { page--; RefreshLibrary(); };
        next.Content = "下一页"; next.Click += (_, _) => { page++; RefreshLibrary(); };
        pageLabel.VerticalAlignment = VerticalAlignment.Center; pageLabel.Margin = new Thickness(8, 0, 14, 0);
        pagination.Children.Add(previous); pagination.Children.Add(pageLabel); pagination.Children.Add(next); footer.Children.Add(pagination);
        status.Foreground = Muted; status.FontSize = 11; status.TextWrapping = TextWrapping.Wrap; status.VerticalAlignment = VerticalAlignment.Center;
        footer.Children.Add(status); Add(layout, footer, 6);

        model.Changed += Refresh;
        model.AssetsChanged += () => { Refresh(); RefreshDownload(); RefreshLibrary(false); };
        Closing += (_, args) => { if (!Exiting) { args.Cancel = true; model.SetRecording(false); Hide(); } };
        Deactivated += (_, _) => { if (model.RecordingKey) model.SetRecording(false); };
        Refresh(); RefreshDownload(); RefreshLibrary();
        if (model.LoadWarning != null) status.Text = model.LoadWarning;
    }

    private static void Add(Grid grid, UIElement child, int row) { Grid.SetRow(child, row); grid.Children.Add(child); }
    private static Style ButtonStyle()
    {
        var style = new Style(typeof(Button));
        style.Setters.Add(new Setter(Control.BackgroundProperty, Card));
        style.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.WhiteSmoke));
        style.Setters.Add(new Setter(Control.BorderBrushProperty, Color("#345163")));
        style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(12, 7, 12, 7)));
        style.Setters.Add(new Setter(FrameworkElement.MarginProperty, new Thickness(0, 0, 8, 0)));
        style.Setters.Add(new Setter(Control.CursorProperty, Cursors.Hand));
        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Control.ForegroundProperty, BackgroundBrush)); style.Triggers.Add(hover);
        return style;
    }
    private static Button Button(string text, Action action)
    { var button = new Button { Content = text }; button.Click += (_, _) => action(); return button; }

    private void Refresh()
    {
        refreshing = true;
        enabled.IsChecked = model.Config.Enabled; shortcut.Text = model.Config.ShortcutLabel;
        record.Content = model.RecordingKey ? "按下新快捷键 · Esc 取消" : "修改按键";
        wheelScale.Value = model.Config.WheelScale; duration.Value = model.Config.DisplayDuration;
        scaleLabel.Text = $"{model.Config.WheelScale:0.0}×"; durationLabel.Text = $"{model.Config.DisplayDuration:0.0} 秒";
        slots.Children.Clear();
        string[] positions = { "↑ 上", "↗ 右上", "→ 右", "↘ 右下", "↓ 下", "↙ 左下", "← 左", "↖ 左上" };
        for (int index = 0; index < 8; index++)
        {
            int slot = index;
            var item = model.Find(model.Config.Slots[index]);
            var content = new StackPanel();
            var slotImage = model.Image(model.Config.Slots[index]);
            content.Children.Add(slotImage == null ? Placeholder(52) : new Image { Source = slotImage, Width = 52, Height = 52 });
            content.Children.Add(new TextBlock { Text = positions[index], FontSize = 11, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 0) });
            var button = new Button { Content = content, Padding = new Thickness(3, 7, 3, 7), ToolTip = item?.Name,
                BorderBrush = index == model.SelectedSlot ? Gold : Color("#294252"), BorderThickness = new Thickness(index == model.SelectedSlot ? 2 : 1) };
            button.Click += (_, _) => { model.SelectedSlot = slot; Refresh(); };
            slots.Children.Add(button);
        }
        status.Text = model.RecordingKey ? "可使用单键或 Ctrl / Alt / Shift / Win 组合键。" : $"关闭窗口后继续在托盘运行 · 槽位 {model.SelectedSlot + 1}：{model.Find(model.Config.Slots[model.SelectedSlot])?.Name}";
        refreshing = false;
    }

    private static FrameworkElement Placeholder(double size) => new Border { Width = size, Height = size, Background = Card,
        Child = new TextBlock { Text = "未下载", Foreground = Muted, FontSize = 11, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };

    private void RefreshDownload()
    {
        downloadStatus.Text = model.DownloadStatus;
        download.Content = model.IsDownloading ? "正在下载…" : model.DownloadFailed > 0 ? "重试下载全部表情" : "一键下载全部表情";
        download.IsEnabled = !model.IsDownloading;
        cancelDownload.Visibility = model.IsDownloading ? Visibility.Visible : Visibility.Collapsed;
        downloadProgress.Visibility = model.IsDownloading ? Visibility.Visible : Visibility.Collapsed;
        downloadProgress.Maximum = Math.Max(1, model.DownloadTotal); downloadProgress.Value = model.DownloadCompleted;
    }

    private void RefreshLibrary(bool resetScroll = true)
    {
        string query = search.Text.Trim();
        filtered = string.IsNullOrEmpty(query) ? model.Catalog : model.Catalog.Where(item => item.Matches(query)).ToList();
        int pages = Math.Max(1, (filtered.Count + PageSize - 1) / PageSize); page = Math.Clamp(page, 0, pages - 1);
        pageLabel.Text = $"{page + 1} / {pages}"; previous.IsEnabled = page > 0; next.IsEnabled = page + 1 < pages;
        library.Children.Clear();
        foreach (var item in filtered.Skip(page * PageSize).Take(PageSize))
        {
            var content = new StackPanel();
            var image = model.Image(item.Id);
            content.Children.Add(image == null ? Placeholder(67) : new Image { Source = image, Width = 67, Height = 67 });
            content.Children.Add(new TextBlock { Text = item.Name, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 100, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 5, 0, 0) });
            var button = new Button { Content = content, IsEnabled = image != null, Padding = new Thickness(2, 7, 2, 7), Margin = new Thickness(0, 0, 7, 7), ToolTip = $"{item.Name}\n{item.Subtitle}\nID: {item.Id}" };
            button.Click += (_, _) => model.Assign(item); library.Children.Add(button);
        }
        count.Text = $"可用 {model.AvailableCount:N0} / {model.Catalog.Count:N0} 个" + (query.Length == 0 ? "" : $" · 找到 {filtered.Count:N0} 个");
        if (filtered.Count == 0) status.Text = "没有匹配表情，试试英文名称、别名或 ID。";
        if (resetScroll) libraryScroll.ScrollToTop();
    }

    private void Import()
    {
        overlay.Cancel(); model.RecordingKey = false; model.ModalOpen = true;
        try
        {
            var dialog = new Microsoft.Win32.OpenFileDialog { Title = "选择一张表情图片", Filter = "图片|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.tif;*.tiff", Multiselect = false };
            if (dialog.ShowDialog(this) != true) return;
            model.Import(dialog.FileName); search.Text = ""; page = (model.Catalog.Count - 1) / PageSize; RefreshLibrary();
        }
        catch (Exception ex) { MessageBox.Show(this, "图片导入失败：" + ex.Message, "EmoteWheel"); }
        finally { model.ModalOpen = false; Refresh(); }
    }
}
