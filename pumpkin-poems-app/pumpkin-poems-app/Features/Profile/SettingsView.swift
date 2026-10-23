import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var confirmReset = false
    #if DEBUG
    @AppStorage(AppClock.dayOffsetKey) private var dayOffset = 0
    #endif

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker(settings.t("文字", "文字"), selection: $settings.script) {
                    Text("繁體中文").tag(Script.hant)
                    Text("简体中文").tag(Script.hans)
                }
                Picker(settings.t("朗讀語言", "朗读语言"), selection: $settings.voice) {
                    Text(settings.t("粵語", "粤语")).tag(VoiceLanguage.cantonese)
                    Text(settings.t("普通話", "普通话")).tag(VoiceLanguage.mandarin)
                }
                if !SpeechPlayer.hasVoice(for: settings.voice) {
                    Text(settings.t("這部裝置未安裝所選語言的朗讀聲音，會使用系統預設聲音。可在「設定 > 輔助使用 > 朗讀內容 > 聲音」下載。",
                                    "这台设备未安装所选语言的朗读声音，会使用系统默认声音。可在“设置 > 辅助功能 > 朗读内容 > 声音”下载。"))
                        .font(.footnote)
                        .foregroundStyle(Color.chestnut)
                }
            } header: {
                Text(settings.t("文字與朗讀", "文字与朗读"))
            } footer: {
                Text(settings.t("文字版本和朗讀語言分開設定，切換不會影響學習記錄。", "文字版本和朗读语言分开设置，切换不会影响学习记录。"))
            }

            Section(settings.t("詩句字號", "诗句字号")) {
                Picker(settings.t("字號", "字号"), selection: $settings.poemScale) {
                    Text(settings.t("小", "小")).tag(0.9)
                    Text(settings.t("標準", "标准")).tag(1.0)
                    Text(settings.t("大", "大")).tag(1.2)
                    Text(settings.t("特大", "特大")).tag(1.4)
                }
                .pickerStyle(.segmented)
                Text("床前明月光")
                    .poemFont()
                    .foregroundStyle(Color.cocoa)
                    .frame(maxWidth: .infinity)
            }

            Section(settings.t("關於內容", "关于内容")) {
                LabeledContent(settings.t("內容版本", "内容版本"), value: PoemLibrary.shared.version)
                Text(settings.t("第一階段內置 12 首詩，全部離線使用。朗讀暫用裝置內置的粵語／普通話聲音，正式錄音審核後會替換。",
                                "第一阶段内置 12 首诗，全部离线使用。朗读暂用设备内置的粤语／普通话声音，正式录音审核后会替换。"))
                    .font(.footnote)
                    .foregroundStyle(Color.chestnut)
            }

            #if DEBUG
            Section {
                Stepper(value: $dayOffset, in: 0...60) {
                    Text(settings.t("模擬日期：今天 + \(dayOffset) 天", "模拟日期：今天 + \(dayOffset) 天"))
                }
            } header: {
                Text(settings.t("演示工具（僅開發版）", "演示工具（仅开发版）"))
            } footer: {
                Text(settings.t("用來演示跨日複習，不會出現在正式版。", "用来演示跨日复习，不会出现在正式版。"))
            }
            #endif

            Section {
                Button(settings.t("清除全部學習記錄", "清除全部学习记录"), role: .destructive) {
                    confirmReset = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(settings.t("設定", "设置"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(settings.t("清除後，學習進度、錯題和遊戲記錄都會刪除，無法復原。", "清除后，学习进度、错题和游戏记录都会删除，无法恢复。"),
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button(settings.t("清除", "清除"), role: .destructive) {
                ProgressStore(context: context).resetAll()
            }
        }
    }
}
