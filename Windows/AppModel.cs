using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
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
    private readonly Dictionary<string, BitmapSource> cache = new();
    private readonly Queue<string> cacheOrder = new();

    public AppModel()
    {
        string settings = Path.Combine(SupportPath, "settings.json");
        if (File.Exists(settings))
        {
            try { Config = JsonSerializer.Deserialize<Configuration>(File.ReadAllText(settings), Json) ?? new(); }
            catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
            { LoadWarning = "设置文件无法读取，已使用默认设置。原文件保留在 settings.json。"; }
        }
        Config.Normalize();
        string catalogFile = Path.Combine(AppContext.BaseDirectory, "Resources", "emotes.json");
        Catalog.AddRange(JsonSerializer.Deserialize<List<Emote>>(File.ReadAllText(catalogFile), Json) ?? new());
        Catalog.AddRange(Config.CustomEmotes);
        for (int index = 0; index < 8; index++)
            if (Find(Config.Slots[index]) == null) Config.Slots[index] = Configuration.DefaultSlots[index];
    }

    public Emote? Find(string id) => Catalog.FirstOrDefault(item => item.Id == id);
    public string PathFor(Emote item) => Path.Combine(item.Id.StartsWith("custom-", StringComparison.Ordinal) ? SupportPath : Path.Combine(AppContext.BaseDirectory, "Resources"), item.Filename);

    public BitmapSource? Image(string id)
    {
        if (cache.TryGetValue(id, out var image)) return image;
        var item = Find(id);
        if (item == null) return null;
        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.DecodePixelWidth = 256;
            bitmap.UriSource = new Uri(PathFor(item)); bitmap.EndInit(); bitmap.Freeze();
            cache[id] = bitmap; cacheOrder.Enqueue(id);
            while (cache.Count > 128) cache.Remove(cacheOrder.Dequeue());
            return bitmap;
        }
        catch (Exception ex) when (ex is IOException or NotSupportedException or UriFormatException or System.Runtime.InteropServices.COMException) { return null; }
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

    public void Assign(Emote emote) { Config.Slots[SelectedSlot] = emote.Id; Save(); }
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
        Catalog.Add(item); Config.CustomEmotes.Add(item); Assign(item);
    }

    public void Reset()
    {
        var imported = Config.CustomEmotes;
        Config = new Configuration { CustomEmotes = imported };
        RecordingKey = false; Save();
    }
}
