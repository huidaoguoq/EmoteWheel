using EmoteWheel;
using System.Text.Json;

int passed = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new Exception(name);
    passed++;
}
var positions = new[] { (0.0, -100.0), (100.0, -100.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0), (-100.0, 100.0), (-100.0, 0.0), (-100.0, -100.0) };
for (int index = 0; index < positions.Length; index++)
    Check(WheelMath.Slot(positions[index].Item1, positions[index].Item2, 55) == index, $"Clockwise slot {index}");
Check(WheelMath.Slot(0, 0, 55) == null && WheelMath.Slot(55, 0, 55) == null, "Center and dead-zone boundary cancel");
Check(WheelMath.Slot(55.01, 0, 55) == 2, "Outside dead-zone commits");
Check(WheelMath.ClampCenter(-1910, -1920, 0, 420) == -1702, "Negative monitor origin clamp");
Check(WheelMath.ClampCenter(1900, 0, 1920, 420) == 1702, "Right edge clamp");
Check(WheelMath.ClampCenter(5, 0, 100, 420) == 50, "Small monitor center");
var invalid = new Configuration { Slots = new[] { "bad" }, WheelScale = double.NaN, DisplayDuration = 20, VirtualKey = 0x10 };
invalid.Normalize();
Check(invalid.Slots.Length == 8 && invalid.Slots[0] == "1505", "Recover malformed slots");
Check(invalid.WheelScale == 1 && invalid.DisplayDuration == 5 && invalid.VirtualKey == 0x59, "Recover malformed key and limits");
var config = new Configuration { VirtualKey = 0x45, KeyLabel = "E", Modifiers = HotkeyModifiers.Control | HotkeyModifiers.Shift };
Check(config.ShortcutLabel == "Ctrl + Shift + E", "Modifier label");
config.Slots[0] = "3239";
Check(new Configuration().Slots[0] == "1505", "Configurations do not share mutable default slots");
var saved = JsonSerializer.Deserialize<Configuration>(JsonSerializer.Serialize(config))!;
Check(saved.Slots[0] == "3239" && saved.Modifiers == config.Modifiers, "Configuration persists selected emote and shortcut");
var item = new Emote { Id = "4361", Name = "这…", Subtitle = "Sweat Drop", Keywords = new[] { "流汗", "刀妹" } };
Check(item.Matches("流汗") && item.Matches("sweat") && item.Matches("4361") && !item.Matches("unworthy"), "Chinese alias, case-insensitive English, ID search");
Console.WriteLine($"{passed} Windows core checks passed");
