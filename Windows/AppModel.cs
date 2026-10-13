using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace EmoteWheel;

public sealed class AppModel
{
    public static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true };
    public string SupportPath { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "EmoteWheel");
    public Configuration Config { get; private set; } = new();
    public List<Emote> Catalog { get; } = new();
    public int SelectedSlot { get; set; }
    public bool RecordingKey { get; set; }
    public bool ModalOpen { get; set; }
    public string? LoadWarning { get; private set; }
    public event Action? Changed;
    public event Action? AssetsChanged;
    public bool IsDownloading { get; private set; }
    public int DownloadCompleted { get; private set; }
    public int DownloadTotal { get; private set; }
    public int DownloadFailed { get; private set; }
    public string DownloadStatus { get; private set; } = "内置 8 个表情；下载后可离线使用全部表情。";
    public int AvailableCount => Catalog.Count(item => available.Contains(item.Id));
    private readonly HashSet<string> available = new();
    private CancellationTokenSource? downloadCancellation;
    private readonly Dictionary<string, BitmapSource> cache = new();
    private readonly Queue<string> cacheOrder = new();

    public AppModel(bool loadSettings = true)
    {
        string settings = Path.Combine(SupportPath, "settings.json");
        if (loadSettings && File.Exists(settings))
        {
            try { Config = JsonSerializer.Deserialize<Configuration>(File.ReadAllText(settings), Json) ?? new(); }
            catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
            { LoadWarning = "设置文件无法读取，已使用默认设置。原文件保留在 settings.json。"; }
        }
        Config.Normalize();
        string catalogFile = Path.Combine(AppContext.BaseDirectory, "Resources", "emotes.json");
        Catalog.AddRange(JsonSerializer.Deserialize<List<Emote>>(File.ReadAllText(catalogFile), Json) ?? new());
        Catalog.AddRange(Config.CustomEmotes);
        foreach (var item in Catalog)
            if (File.Exists(PathFor(item))) available.Add(item.Id);
        for (int index = 0; index < 8; index++)
            if (Find(Config.Slots[index]) == null) Config.Slots[index] = Configuration.DefaultSlots[index];
        if (AvailableCount == Catalog.Count) DownloadStatus = $"全部 {Catalog.Count:N0} 个表情已可离线使用。";
        else if (AvailableCount > 8) DownloadStatus = $"已就绪 {AvailableCount:N0} 个表情，可继续下载其余表情。";
    }

    public Emote? Find(string id) => Catalog.FirstOrDefault(item => item.Id == id);
    public string PathFor(Emote item)
    {
        if (item.Id.StartsWith("custom-", StringComparison.Ordinal)) return Path.Combine(SupportPath, item.Filename);
        string downloaded = Path.Combine(SupportPath, "emotes", item.Id + ".png");
        return File.Exists(downloaded) ? downloaded : BundledPath(item);
    }
    private static string BundledPath(Emote item) => Path.Combine(AppContext.BaseDirectory, "Resources", item.Filename);
    public bool IsAvailable(Emote item) => available.Contains(item.Id);

    public BitmapSource? Image(string id)
    {
        if (cache.TryGetValue(id, out var image)) return image;
        var item = Find(id);
        if (item == null) return null;
        foreach (string path in new[] { PathFor(item), BundledPath(item) }.Distinct())
        {
            try
            {
                if (!File.Exists(path)) continue;
                var bitmap = new BitmapImage();
                bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.DecodePixelWidth = 256;
                using var stream = File.OpenRead(path);
                bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze();
                cache[id] = bitmap; cacheOrder.Enqueue(id);
                while (cache.Count > 128) cache.Remove(cacheOrder.Dequeue());
                return bitmap;
            }
            catch (Exception ex) when (ex is IOException or FileFormatException or UnauthorizedAccessException or NotSupportedException or UriFormatException or ArgumentException or System.Runtime.InteropServices.COMException) { }
        }
        available.Remove(id);
        return null;
    }

    public void CancelDownload()
    {
        if (downloadCancellation == null) return;
        DownloadStatus = "正在取消下载…";
        downloadCancellation.Cancel();
        AssetsChanged?.Invoke();
    }

    public async Task DownloadAll()
    {
        if (IsDownloading) return;
        IsDownloading = true; DownloadCompleted = 0; DownloadFailed = 0;
        DownloadTotal = Catalog.Count(item => !item.Id.StartsWith("custom-", StringComparison.Ordinal));
        DownloadStatus = "正在检查已有表情…";
        using var cancellation = new CancellationTokenSource();
        downloadCancellation = cancellation;
        AssetsChanged?.Invoke();
        var dispatcher = Application.Current.Dispatcher;
        var lastUpdate = DateTime.MinValue;
        try
        {
            string folder = Path.Combine(SupportPath, "emotes");
            Directory.CreateDirectory(folder);
            var sources = EmoteDownloads.Sources();
            DownloadTotal = sources.Count;
            await Parallel.ForEachAsync(sources, new ParallelOptions { MaxDegreeOfParallelism = 4, CancellationToken = cancellation.Token }, async (source, token) =>
            {
                string id = source.Id.ToString(System.Globalization.CultureInfo.InvariantCulture);
                string destination = Path.Combine(folder, id + ".png");
                bool success;
                try
                {
                    if (!EmoteDownloads.ValidImage(destination) && !EmoteDownloads.ValidImage(Path.Combine(AppContext.BaseDirectory, "Resources", "emotes", id + ".png")))
                        await EmoteDownloads.Download(source, destination, token);
                    success = true;
                }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                catch (Exception ex) when (ex is IOException or InvalidDataException or UnauthorizedAccessException or System.Net.Http.HttpRequestException or OperationCanceledException)
                { success = false; }
                await dispatcher.InvokeAsync(() =>
                {
                    DownloadCompleted++;
                    if (success) available.Add(id); else { available.Remove(id); DownloadFailed++; }
                    DownloadStatus = $"已处理 {DownloadCompleted:N0} / {DownloadTotal:N0} 个 · 失败 {DownloadFailed:N0} 个";
                    if ((DateTime.UtcNow - lastUpdate).TotalMilliseconds >= 250)
                    { lastUpdate = DateTime.UtcNow; AssetsChanged?.Invoke(); }
                });
            });
            DownloadStatus = DownloadFailed == 0 ? $"全部 {DownloadTotal:N0} 个表情已可离线使用。" : $"下载完成，{DownloadFailed:N0} 个失败；点击重试会保留已下载的表情。";
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        { DownloadStatus = $"已取消，保留已下载的表情；可随时继续下载。"; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or ArgumentException)
        { DownloadStatus = "下载失败：" + ex.Message; }
        finally
        {
            downloadCancellation = null; IsDownloading = false;
            AssetsChanged?.Invoke(); Changed?.Invoke();
        }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(SupportPath);
            string destination = Path.Combine(SupportPath, "settings.json");
            string temporary = destination + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(Config, Json));
            File.Move(temporary, destination, true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        { MessageBox.Show("设置保存失败：" + ex.Message, "EmoteWheel"); }
        Changed?.Invoke();
    }

    public void Assign(Emote emote) { if (Image(emote.Id) == null) return; Config.Slots[SelectedSlot] = emote.Id; Save(); }
    public void SetRecording(bool value) { RecordingKey = value; Changed?.Invoke(); }

    public void Import(string path)
    {
        var source = new BitmapImage();
        source.BeginInit(); source.CacheOption = BitmapCacheOption.OnLoad; source.DecodePixelWidth = 512;
        source.UriSource = new Uri(path); source.EndInit(); source.Freeze();
        double scale = Math.Min(256.0 / source.PixelWidth, 256.0 / source.PixelHeight);
        double width = source.PixelWidth * scale, height = source.PixelHeight * scale;
        var visual = new DrawingVisual();
        using (var drawing = visual.RenderOpen()) drawing.DrawImage(source, new Rect((256 - width) / 2, (256 - height) / 2, width, height));
        var normalized = new RenderTargetBitmap(256, 256, 96, 96, PixelFormats.Pbgra32); normalized.Render(visual);
        string id = "custom-" + Guid.NewGuid().ToString("N");
        string filename = "imports/" + id + ".png";
        Directory.CreateDirectory(Path.Combine(SupportPath, "imports"));
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(normalized));
        using (var stream = File.Create(Path.Combine(SupportPath, filename))) encoder.Save(stream);
        var item = new Emote { Id = id, Name = Path.GetFileNameWithoutExtension(path), Subtitle = "我的表情", Filename = filename };
        Catalog.Add(item); Config.CustomEmotes.Add(item); available.Add(id); Assign(item);
    }

    public void Reset()
    {
        var imported = Config.CustomEmotes;
        Config = new Configuration { CustomEmotes = imported };
        RecordingKey = false; Save();
    }
}
