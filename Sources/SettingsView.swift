import SwiftUI
import AppKit

private enum Theme {
    static let background = Color(red: 0.039, green: 0.071, blue: 0.110)
    static let sidebar = Color(red: 0.027, green: 0.051, blue: 0.086)
    static let surface = Color(red: 0.059, green: 0.098, blue: 0.145)
    static let raised = Color(red: 0.079, green: 0.125, blue: 0.180)
    static let gold = Color(red: 0.82, green: 0.68, blue: 0.43)
    static let cyan = Color(red: 0.35, green: 0.79, blue: 0.80)
    static let text = Color(red: 0.91, green: 0.93, blue: 0.94)
    static let muted = Color(red: 0.48, green: 0.57, blue: 0.65)
    static let line = Color.white.opacity(0.075)
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var libraryQuery = ""

    private var selectedEmoteID: String? {
        guard model.config.slots.indices.contains(model.selectedSlot) else { return nil }
        return model.config.slots[model.selectedSlot]
    }

    private var statusColor: Color {
        model.config.enabled ? (model.permissionGranted ? Theme.cyan : Theme.gold) : Theme.muted
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 224)
            Rectangle().fill(Theme.line).frame(width: 1)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    pageHeader
                    HStack(alignment: .top, spacing: 16) {
                        wheelPanel.frame(maxWidth: .infinity)
                        controlsPanel.frame(width: 278)
                    }
                    libraryPanel
                    footer
                }
                .padding(.horizontal, 25)
                .padding(.top, 27)
                .padding(.bottom, 22)
            }
        }
        .frame(minWidth: 1000, minHeight: 720)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .tint(Theme.gold)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Theme.gold.opacity(0.8), lineWidth: 1)
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(45))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.gold.opacity(0.12))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(45))
                    Image(systemName: "sparkle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.gold)
                }
                .frame(width: 43, height: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text("EMOTE").tracking(3.7)
                    Text("WHEEL").tracking(3.0)
                }
                .font(.system(size: 19, weight: .semibold, design: .rounded))
            }
            Text("桌面表情轮盘")
                .font(.system(size: 11))
                .tracking(3)
                .foregroundStyle(Theme.muted)
                .padding(.top, 17)

            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 27)

            HStack(spacing: 9) {
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 15))
                Text("我的轮盘").font(.system(size: 13, weight: .medium))
                Spacer()
                Circle().fill(Theme.gold).frame(width: 4, height: 4)
            }
            .foregroundStyle(Theme.gold)
            .padding(.horizontal, 13)
            .frame(height: 41)
            .background(Theme.gold.opacity(0.085), in: RoundedRectangle(cornerRadius: 9))

            shortcutCard.padding(.top, 26)

            VStack(alignment: .leading, spacing: 19) {
                Text("一键，表达此刻")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text.opacity(0.85))
                instruction("01", title: "按住快捷键", detail: "在鼠标位置展开轮盘")
                instruction("02", title: "移动鼠标", detail: "指向想发送的表情")
                instruction("03", title: "松开发送", detail: "回到中心或 Esc 取消")
            }
            .padding(.top, 29)

            Spacer(minLength: 30)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 13))
                    .padding(.top, 2)
                Text("表情悬浮显示在你的桌面上，\n不会发送到游戏或聊天中。")
                    .font(.system(size: 10))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.muted)
            Text("MADE FOR YOUR MOMENT")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1.25)
                .foregroundStyle(Theme.muted.opacity(0.55))
                .padding(.top, 20)
        }
        .padding(.horizontal, 23)
        .padding(.top, 39)
        .padding(.bottom, 28)
        .background(Theme.sidebar)
    }

    private var shortcutCard: some View {
        VStack(spacing: 11) {
            Text("HOLD TO EXPRESS")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1.7)
                .foregroundStyle(Theme.muted)
            Text(model.shortcutLabel)
                .font(.system(size: model.shortcutLabel.count > 4 ? 29 : 44, weight: .light, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Theme.gold)
                .frame(height: 51)
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 4, height: 4)
                Text(model.config.enabled ? (model.permissionGranted ? "按住唤出轮盘" : "全局按键待授权") : "轮盘已暂停")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Theme.gold.opacity(0.065), Theme.surface.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.17), lineWidth: 1))
        }
    }

    private func instruction(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.gold.opacity(0.75))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("把情绪，放进快捷键。")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(0.6)
                Text("选好你的表情，随时回应精彩瞬间。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 5, height: 5)
                Text(model.config.enabled ? (model.permissionGranted ? "轮盘已启用" : "待授权") : "轮盘已暂停")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(statusColor.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.12), lineWidth: 1))
        }
    }

    private var wheelPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("轮盘配置").font(.system(size: 12, weight: .semibold))
                Text("/  8 个位置")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.gold)
            }
            .padding(.horizontal, 18)
            .padding(.top, 17)

            wheelDiagram.frame(height: 261)

            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.gold).frame(width: 3, height: 12)
                Text(String(format: "%02d", model.selectedSlot + 1))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.gold)
                Text(selectedEmoteID.flatMap { model.emote(for: $0)?.name } ?? "选择一个位置")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("点击下方表情替换")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 17)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.line, lineWidth: 1))
    }

    private var wheelDiagram: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.gold.opacity(0.065), Color.clear], center: .center, startRadius: 35, endRadius: 137))
                .frame(width: 278, height: 278)
            Circle().stroke(Theme.gold.opacity(0.23), lineWidth: 1).frame(width: 242, height: 242)
            Circle().stroke(Theme.gold.opacity(0.08), lineWidth: 1).frame(width: 252, height: 252)

            ForEach(0..<8, id: \.self) { index in
                ThemeWheelSector(index: index)
                    .fill(index == model.selectedSlot ? Theme.gold.opacity(0.14) : Color.white.opacity(index.isMultiple(of: 2) ? 0.012 : 0.025))
                    .overlay(ThemeWheelSector(index: index).stroke(index == model.selectedSlot ? Theme.gold.opacity(0.7) : Theme.line, lineWidth: 0.75))
                    .frame(width: 242, height: 242)
                    .onTapGesture { model.selectedSlot = index }
            }

            ForEach(0..<8, id: \.self) { index in
                wheelSlot(index)
                    .offset(x: sin(Double(index) * .pi / 4) * 90,
                            y: -cos(Double(index) * .pi / 4) * 90)
            }

            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Theme.gold.opacity(0.85))
                Text("松开即发送").font(.system(size: 9, weight: .medium))
                Text("中心取消")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.muted)
            }
            .frame(width: 82, height: 82)
            .background(Theme.background, in: Circle())
            .overlay(Circle().stroke(Theme.gold.opacity(0.25), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private func wheelSlot(_ index: Int) -> some View {
        let id = model.config.slots.indices.contains(index) ? model.config.slots[index] : ""
        let selected = model.selectedSlot == index
        return Button {
            model.selectedSlot = index
        } label: {
            ZStack(alignment: .bottomTrailing) {
                emoteImage(id, size: 53)
                    .shadow(color: selected ? Theme.gold.opacity(0.24) : Color.black.opacity(0.3), radius: 7, y: 3)
                    .frame(width: 60, height: 59)
                Text(String(index + 1))
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? Theme.background : Theme.muted)
                    .frame(width: 13, height: 13)
                    .background(selected ? Theme.gold : Theme.background, in: Circle())
                    .overlay(Circle().stroke(selected ? Theme.gold : Theme.line, lineWidth: 1))
                    .offset(x: -2, y: -1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("位置 \(index + 1)：\(model.emote(for: id)?.name ?? "未配置")")
        .accessibilityLabel("表情位置 \(index + 1)，\(model.emote(for: id)?.name ?? "未配置")")
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("唤出设置").font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("启用桌面轮盘", isOn: $model.config.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("启用桌面轮盘")
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("全局快捷键").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(model.isRecordingKey ? "Esc 取消" : "点击修改")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted.opacity(0.75))
                }
                Button { model.startRecording() } label: {
                    HStack {
                        Image(systemName: "keyboard").font(.system(size: 15)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(model.isRecordingKey ? "按下新的快捷键…" : model.shortcutLabel)
                            .font(.system(size: model.isRecordingKey ? 11 : 17, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.gold)
                        Spacer()
                        Image(systemName: model.isRecordingKey ? "record.circle" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.gold.opacity(0.65))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Theme.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.gold.opacity(model.isRecordingKey ? 0.8 : 0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 9) {
                settingSlider("轮盘大小", value: $model.config.wheelScale, range: 0.8...1.3, step: 0.05, label: "\(Int((model.config.wheelScale * 100).rounded()))%")
                settingSlider("表情停留", value: $model.config.displayDuration, range: 1...5, step: 0.5, label: String(format: "%.1f 秒", model.config.displayDuration))
            }

            HStack {
                Toggle("发送音效", isOn: $model.config.soundEnabled)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button { model.preview() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 8))
                        Text("试一试").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 14)
                    .frame(height: 29)
                    .background(Theme.gold, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("预览桌面表情轮盘")
            }

            permissionRow
        }
        .padding(17)
        .frame(minHeight: 324)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.line, lineWidth: 1))
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, label: String) -> some View {
        VStack(spacing: 1) {
            HStack {
                Text(title).font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer()
                Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.text.opacity(0.85))
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.mini)
                .accessibilityLabel(title)
        }
    }

    private var permissionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                Text("跨应用使用权限")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("刷新状态") { model.refreshPermissions() }
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.gold)
                    .buttonStyle(.plain)
            }
            permissionButton("输入监控", granted: model.inputMonitoringGranted) {
                model.requestInputMonitoring()
            }
            permissionButton("辅助功能", granted: model.accessibilityGranted) {
                model.requestAccessibility()
            }
            Text(model.permissionGranted ? "输入保护已开启 · 打字时不触发" : "系统已开启但仍未生效时，请退出并重新打开应用。")
                .font(.system(size: 9))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    private func permissionButton(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: granted ? "checkmark.shield" : "lock.shield")
                    .font(.system(size: 11))
                Text(title).font(.system(size: 10, weight: .medium))
                Spacer(minLength: 0)
                Text(granted ? "已就绪" : "未生效").font(.system(size: 9))
                Image(systemName: "arrow.up.right").font(.system(size: 8))
            }
            .foregroundStyle(granted ? Theme.cyan.opacity(0.85) : Theme.gold)
            .frame(minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开\(title)系统设置")
    }

    private var libraryPanel: some View {
        let query = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let emotes = query.isEmpty ? model.catalog : model.catalog.filter {
            $0.name.localizedStandardContains(query) ||
            $0.subtitle.localizedStandardContains(query) ||
            $0.id.localizedStandardContains(query) ||
            ($0.keywords?.contains { $0.localizedStandardContains(query) } ?? false)
        }
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("表情收藏").font(.system(size: 13, weight: .semibold))
                        Text(String(model.catalog.count))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.raised, in: Capsule())
                    }
                    Text("选择一个表情，装备到位置 \(model.selectedSlot + 1)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { model.importImage() } label: {
                    Label("导入图片", systemImage: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.text.opacity(0.85))
                        .padding(.horizontal, 12)
                        .frame(height: 29)
                        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            downloadPanel

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                TextField("搜索名称、别名或 ID", text: $libraryQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .accessibilityLabel("搜索表情")
                if !libraryQuery.isEmpty {
                    Button { libraryQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                    .accessibilityLabel("清除搜索")
                }
                Text(query.isEmpty ? "全部 \(emotes.count) 个" : "\(emotes.count) 个结果")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1))

            if emotes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: query.isEmpty ? "photo.badge.plus" : "magnifyingglass")
                        .font(.system(size: 25, weight: .light))
                    Text(query.isEmpty ? "导入喜欢的图片，开始配置你的轮盘。" : "没有找到相关表情，试试其他名称或 ID。")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 155)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                    ForEach(emotes) { emote in
                        libraryTile(emote)
                    }
                }
            }
        }
    }

    private var downloadPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("已就绪 \(model.readyEmoteCount) / \(model.standardEmoteCount) 个表情" +
                         (model.downloadFailures > 0 ? " · 失败 \(model.downloadFailures) 个" : ""))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(model.downloadStatus.isEmpty ? "内置 8 个常用表情，下载完整图库后可离线使用。" : model.downloadStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if model.isDownloading {
                    Button("取消下载") { model.cancelDownload() }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.gold)
                } else {
                    Button { model.downloadAllEmotes() } label: {
                        Label(model.downloadFailures > 0 ? "重试下载" : "一键下载全部", systemImage: "arrow.down.circle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 12)
                            .frame(height: 29)
                            .background(Theme.gold, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.downloadAllowed)
                }
            }
            if model.isDownloading {
                ProgressView(value: Double(model.readyEmoteCount), total: Double(max(model.standardEmoteCount, 1)))
                    .progressViewStyle(.linear)
                    .tint(Theme.gold)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
    }

    private func libraryTile(_ emote: Emote) -> some View {
        let selected = emote.id == selectedEmoteID
        let available = model.availableEmoteIDs.contains(emote.id)
        return Button { model.assign(emote) } label: {
            VStack(spacing: 4) {
                emoteImage(emote.id, size: 48)
                    .frame(height: 49)
                    .shadow(color: Color.black.opacity(0.22), radius: 4, y: 3)
                Text(emote.name)
                    .font(.system(size: 9, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.gold : Theme.text.opacity(0.73))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity)
            .frame(height: 79)
            .background(selected ? Theme.gold.opacity(0.10) : Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Theme.gold.opacity(0.75) : Theme.line, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.gold)
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(ThemeLibraryButtonStyle())
        .disabled(!available)
        .opacity(available ? 1 : 0.55)
        .help(available ? (emote.subtitle.isEmpty ? emote.name : "\(emote.name) · \(emote.subtitle)") : "\(emote.name) · 尚未下载，点击上方一键下载全部")
        .accessibilityLabel(available ? "将\(emote.name)装备到位置\(model.selectedSlot + 1)" : "\(emote.name)，尚未下载")
    }

    @ViewBuilder
    private func emoteImage(_ id: String, size: CGFloat) -> some View {
        if let image = model.image(for: id) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: size * 0.6, weight: .ultraLight))
                .foregroundStyle(Theme.gold.opacity(0.45))
                .frame(width: size, height: size)
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: model.errorMessage == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 9))
                    .padding(.top, 1)
                Text(model.errorMessage ?? (model.status.isEmpty ? "设置自动保存 · 随心配置，即刻生效" : model.status))
                    .font(.system(size: 9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(model.errorMessage == nil ? Theme.muted : Theme.gold)
            Spacer(minLength: 4)
            Button("恢复默认") { model.resetDefaults() }
                .font(.system(size: 9))
                .foregroundStyle(Theme.muted)
                .buttonStyle(.plain)
        }
        .padding(.top, 1)
    }
}

private struct ThemeWheelSector: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.37
        let start = Double(index) * 45 - 112.5
        let end = start + 45
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct ThemeLibraryButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
