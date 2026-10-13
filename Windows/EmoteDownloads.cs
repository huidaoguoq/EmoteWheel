using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;

namespace EmoteWheel;

internal sealed class EmoteSource
{
    public int Id { get; set; }
    public string Url { get; set; } = "";
}

internal static class EmoteDownloads
{
    private static readonly HttpClient Client = CreateClient();
    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("EmoteWheel-asset-downloader/1.0");
        return client;
    }

    public static List<EmoteSource> Sources() => JsonSerializer.Deserialize<List<EmoteSource>>(
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Resources", "emotes-sources.json")), AppModel.Json) ?? new();

    // The CDN may optimize PNG bytes, so validate the format and decoded image instead of a historical file hash.
    internal static bool ValidImage(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            Validate(stream);
            return true;
        }
        catch (Exception ex) when (ex is IOException or InvalidDataException or FileFormatException or UnauthorizedAccessException or NotSupportedException or ArgumentException or System.Runtime.InteropServices.COMException)
        { return false; }
    }

    private static void Validate(Stream stream)
    {
        Span<byte> header = stackalloc byte[8];
        if (stream.Read(header) != 8 || !header.SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }))
            throw new InvalidDataException("下载内容不是 PNG 图片。");
        stream.Position = 0;
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        if (decoder.Frames.Count == 0 || decoder.Frames[0].PixelWidth <= 0 || decoder.Frames[0].PixelHeight <= 0)
            throw new InvalidDataException("下载的 PNG 无法解码。");
        // Materialize pixels before the file is committed; lazy decoder errors must not poison the offline cache.
        var image = decoder.Frames[0];
        int stride = checked((image.PixelWidth * image.Format.BitsPerPixel + 7) / 8);
        image.CopyPixels(new byte[checked(stride * image.PixelHeight)], stride, 0);
    }

    public static async Task Download(EmoteSource source, string destination, CancellationToken cancellation)
    {
        for (int attempt = 0; ; attempt++)
        {
            string temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using var response = await Client.GetAsync(source.Url, HttpCompletionOption.ResponseHeadersRead, cancellation).ConfigureAwait(false);
                response.EnsureSuccessStatusCode();
                await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true))
                {
                    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
                    timeout.CancelAfter(TimeSpan.FromSeconds(30));
                    await response.Content.CopyToAsync(output, timeout.Token).ConfigureAwait(false);
                }
                if (!ValidImage(temporary)) throw new InvalidDataException("图片验证失败。");
                cancellation.ThrowIfCancellationRequested();
                File.Move(temporary, destination, true);
                return;
            }
            catch (Exception ex) when (!cancellation.IsCancellationRequested && attempt < 2 &&
                ex is HttpRequestException or IOException or InvalidDataException or OperationCanceledException)
            { await Task.Delay(500 * (attempt + 1), cancellation).ConfigureAwait(false); }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
    }
}
