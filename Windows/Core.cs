using System;
using System.Collections.Generic;
using System.Linq;

namespace EmoteWheel;

public sealed class Emote
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Subtitle { get; set; } = "";
    public string Filename { get; set; } = "";
    public string[]? Keywords { get; set; }
    public bool Matches(string query) => new[] { Id, Name, Subtitle }.Concat(Keywords ?? Array.Empty<string>())
        .Any(value => value.Contains(query, StringComparison.OrdinalIgnoreCase));
}

[Flags]
public enum HotkeyModifiers { None = 0, Control = 1, Alt = 2, Shift = 4, Windows = 8 }

public sealed class Configuration
{
    public static readonly string[] DefaultSlots = { "1505", "1459", "3159", "3154", "1506", "1498", "1499", "1030" };
    public bool Enabled { get; set; } = true;
    public int VirtualKey { get; set; } = 0x59;
    public string KeyLabel { get; set; } = "Y";
    public HotkeyModifiers Modifiers { get; set; }
    public string[] Slots { get; set; } = (string[])DefaultSlots.Clone();
    public double WheelScale { get; set; } = 1;
    public double DisplayDuration { get; set; } = 2.4;
    public List<Emote> CustomEmotes { get; set; } = new();

    public string ShortcutLabel =>
        (Modifiers.HasFlag(HotkeyModifiers.Control) ? "Ctrl + " : "") +
        (Modifiers.HasFlag(HotkeyModifiers.Alt) ? "Alt + " : "") +
        (Modifiers.HasFlag(HotkeyModifiers.Shift) ? "Shift + " : "") +
        (Modifiers.HasFlag(HotkeyModifiers.Windows) ? "Win + " : "") + KeyLabel;

    public void Normalize()
    {
        if (Slots == null || Slots.Length != 8) Slots = (string[])DefaultSlots.Clone();
        if (VirtualKey < 1 || VirtualKey > 254 || IsModifier(VirtualKey)) { VirtualKey = 0x59; KeyLabel = "Y"; Modifiers = 0; }
        if (!double.IsFinite(WheelScale)) WheelScale = 1;
        if (!double.IsFinite(DisplayDuration)) DisplayDuration = 2.4;
        WheelScale = Math.Clamp(WheelScale, .8, 1.3);
        DisplayDuration = Math.Clamp(DisplayDuration, 1, 5);
        CustomEmotes ??= new();
    }

    public static bool IsModifier(int key) => key is 0x10 or 0x11 or 0x12 or 0x5B or 0x5C or >= 0xA0 and <= 0xA5;
}

public static class WheelMath
{
    // Windows screen coordinates: positive Y points down; slot 0 is north.
    public static int? Slot(double dx, double dy, double deadZone)
    {
        if (Math.Sqrt(dx * dx + dy * dy) <= deadZone) return null;
        return ((int)Math.Floor((Math.Atan2(dx, -dy) + Math.PI / 8) / (Math.PI / 4)) + 8) % 8;
    }

    public static double ClampCenter(double pointer, double min, double max, double size)
    {
        double inset = size / 2 + 8;
        return max - min <= inset * 2 ? (min + max) / 2 : Math.Clamp(pointer, min + inset, max - inset);
    }
}
