using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace EmoteWheel;

internal sealed class OverlayWindow : Window
{
    private readonly bool interactive;
    public OverlayWindow(double size, bool interactive = false)
    {
        this.interactive = interactive;
        Width = size; Height = size; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent; Topmost = true;
        ShowInTaskbar = false; ShowActivated = false; Focusable = false;
    }
    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var handle = new WindowInteropHelper(this).Handle;
        long style = Native.GetWindowLongPtr(handle, -20).ToInt64() | 0x08000000 | 0x00000080;
        if (!interactive) style |= 0x00000020;
        Native.SetWindowLongPtr(handle, -20, new IntPtr(style));
        HwndSource.FromHwnd(handle)?.AddHook((IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled) =>
        {
            if (message == 0x21) { handled = true; return new IntPtr(3); } // MA_NOACTIVATE
            return IntPtr.Zero;
        });
    }
    public void Place(int left, int top, int size)
    {
        Native.SetWindowPos(new WindowInteropHelper(this).Handle, new IntPtr(-1), left, top, size, size, 0x0010 | 0x0040);
    }
}

internal sealed class WheelView : FrameworkElement
{
    private readonly AppModel model;
    private int? selected;
    public int? Selected { get => selected; set { if (selected != value) { selected = value; InvalidateVisual(); } } }
    public bool Preview { get; set; }
    private static readonly Brush Gold = Brush("#C7A35E"), Cyan = Brush("#59E8D9");
    private static Brush Brush(string color) => (Brush)new BrushConverter().ConvertFromString(color)!;
    public WheelView(AppModel model) { this.model = model; }
    protected override void OnRender(DrawingContext drawing)
    {
        base.OnRender(drawing);
        double scale = ActualWidth / 420;
        drawing.PushTransform(new ScaleTransform(scale, scale));
        var center = new Point(210, 210);
        drawing.DrawEllipse(Brush("#F9091822"), new Pen(Gold, 1.5), center, 165, 165);
        for (int index = 0; index < 8; index++)
        {
            double angle = index * Math.PI / 4;
            var geometry = new StreamGeometry();
            using (var shape = geometry.Open())
            {
                Point Outer(double a) => new(210 + Math.Sin(a) * 160, 210 - Math.Cos(a) * 160);
                Point Inner(double a) => new(210 + Math.Sin(a) * 58, 210 - Math.Cos(a) * 58);
                double from = angle - .38, to = angle + .38;
                shape.BeginFigure(Outer(from), true, true);
                shape.ArcTo(Outer(to), new Size(160, 160), 0, false, SweepDirection.Clockwise, true, false);
                shape.LineTo(Inner(to), true, false);
                shape.ArcTo(Inner(from), new Size(58, 58), 0, false, SweepDirection.Counterclockwise, true, false);
            }
            bool active = Selected == index;
            drawing.DrawGeometry(Brush(active ? "#1C474D" : "#0B1A24"), new Pen(active ? Cyan : Brush("#604F4126"), active ? 1.8 : .7), geometry);
            var bitmap = model.Image(model.Config.Slots[index]);
            double side = active ? 80 : 68;
            if (bitmap != null) drawing.DrawImage(bitmap, new Rect(210 + Math.Sin(angle) * 112 - side / 2, 210 - Math.Cos(angle) * 112 - side / 2, side, side));
        }
        drawing.DrawEllipse(Brush("#091722"), new Pen(Gold, 1), center, 55, 55);
        Text(drawing, Selected == null ? "✦" : "↑", 210, 181, 29, Selected == null ? Gold : Cyan);
        Text(drawing, Selected == null ? "移回此处取消" : Preview ? "点击展示" : "松开展示", 210, 220, 10, Brushes.LightGray);
        Text(drawing, Selected is int slot ? model.Find(model.Config.Slots[slot])?.Name ?? "" : Preview ? "移动选择 · 点击展示 · Esc 取消" : model.Config.ShortcutLabel + "  /  移动选择 · 松开展示", 210, 394, 12, Brushes.WhiteSmoke);
        drawing.Pop();
    }
    private void Text(DrawingContext drawing, string value, double x, double y, double size, Brush brush)
    {
        var text = new FormattedText(value, CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface("Microsoft YaHei UI"), size, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        drawing.DrawText(text, new Point(x - text.Width / 2, y));
    }
}

internal sealed class OverlayController : IDisposable
{
    private readonly AppModel model;
    private OverlayWindow? wheel, effect;
    private WheelView? view;
    private readonly DispatcherTimer tracking;
    private readonly DispatcherTimer effectTimer;
    private double centerX, centerY, wheelPixels;
    private Native.Point initialPointer;
    private bool moved;
    private DateTime previewDeadline;
    public bool Active => wheel != null;
    public bool IsPreview { get; private set; }
    public IntPtr ForegroundAtShow { get; private set; }

    public OverlayController(AppModel model)
    {
        this.model = model;
        tracking = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) }; tracking.Tick += (_, _) => Track();
        effectTimer = new DispatcherTimer(); effectTimer.Tick += (_, _) => HideEffect();
    }

    public void Show(bool preview)
    {
        Cancel(); HideEffect();
        ForegroundAtShow = Native.GetForegroundWindow();
        Native.GetCursorPos(out initialPointer);
        var screen = Forms.Screen.FromPoint(new System.Drawing.Point(initialPointer.X, initialPointer.Y)).WorkingArea;
        double dpi = Dpi(initialPointer);
        double size = Math.Min(420 * model.Config.WheelScale, (Math.Min(screen.Width, screen.Height) - 20) / dpi);
        wheelPixels = size * dpi;
        centerX = WheelMath.ClampCenter(preview ? screen.Left + screen.Width / 2.0 : initialPointer.X, screen.Left, screen.Right, wheelPixels);
        centerY = WheelMath.ClampCenter(preview ? screen.Top + screen.Height / 2.0 : initialPointer.Y, screen.Top, screen.Bottom, wheelPixels);
        IsPreview = preview; moved = false; previewDeadline = DateTime.UtcNow.AddSeconds(15);
        view = new WheelView(model) { Preview = preview };
        wheel = new OverlayWindow(size, preview) { Content = view };
        if (preview)
        {
            wheel.MouseLeftButtonDown += (_, _) => { var picked = TakeSelection(); if (picked != null) Display(picked.Value.Id, picked.Value.X, picked.Value.Y); };
            wheel.MouseRightButtonDown += (_, _) => Cancel();
        }
        wheel.Show(); wheel.Place((int)Math.Round(centerX - wheelPixels / 2), (int)Math.Round(centerY - wheelPixels / 2), (int)Math.Round(wheelPixels));
        wheel.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(110)));
        tracking.Start();
    }

    private void Track()
    {
        if (wheel == null || view == null) return;
        if (IsPreview && DateTime.UtcNow > previewDeadline) { Cancel(); return; }
        Native.GetCursorPos(out var pointer);
        if (Math.Abs(pointer.X - initialPointer.X) + Math.Abs(pointer.Y - initialPointer.Y) > 3) moved = true;
        view.Selected = moved ? WheelMath.Slot(pointer.X - centerX, pointer.Y - centerY, 55 * wheelPixels / 420) : null;
    }

    public (string Id, double X, double Y)? TakeSelection()
    {
        Track();
        (string, double, double)? result = view?.Selected is int slot ? (model.Config.Slots[slot], centerX, centerY) : null;
        Cancel(); return result;
    }

    public void Display(string id, double x, double y)
    {
        HideEffect();
        var bitmap = model.Image(id); if (bitmap == null) return;
        var point = new Native.Point { X = (int)x, Y = (int)y };
        double dpi = Dpi(point), size = 240 * dpi;
        var screen = Forms.Screen.FromPoint(new System.Drawing.Point(point.X, point.Y)).WorkingArea;
        x = WheelMath.ClampCenter(x, screen.Left, screen.Right, size); y = WheelMath.ClampCenter(y, screen.Top, screen.Bottom, size);
        var scale = new ScaleTransform(1, 1);
        var image = new Image { Source = bitmap, Margin = new Thickness(30), Stretch = Stretch.Uniform,
            RenderTransform = scale, RenderTransformOrigin = new Point(.5, .5),
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 14, ShadowDepth = 3, Opacity = .45 } };
        effect = new OverlayWindow(240) { Content = image };
        effect.Show(); effect.Place((int)(x - size / 2), (int)(y - size / 2), (int)size);
        var pop = new DoubleAnimation(.35, 1, TimeSpan.FromMilliseconds(380)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = .5 } };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, pop); scale.BeginAnimation(ScaleTransform.ScaleYProperty, pop);
        effect.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(250)) { BeginTime = TimeSpan.FromSeconds(model.Config.DisplayDuration - .25) });
        effectTimer.Interval = TimeSpan.FromSeconds(model.Config.DisplayDuration); effectTimer.Start();
    }

    private static double Dpi(Native.Point point)
    {
        return Native.GetDpiForMonitor(Native.MonitorFromPoint(point, 2), 0, out uint x, out _) == 0 ? x / 96.0 : 1;
    }
    public void Cancel() { tracking.Stop(); wheel?.Close(); wheel = null; view = null; IsPreview = false; }
    private void HideEffect() { effectTimer.Stop(); effect?.Close(); effect = null; }
    public void Dispose() { Cancel(); HideEffect(); }
}
