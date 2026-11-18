import SwiftData
import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SpeechPlayer.self) private var speech
    @Environment(\.modelContext) private var context
    @State private var confirmReset = false
    #if DEBUG
    @AppStorage(AppClock.dayOffsetKey) private var dayOffset = 0
    #endif

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section(settings.t("學習計劃", "学习计划")) {
                Picker(settings.t("目標年級", "目标年级"), selection: Binding(
                    get: { settings.targetGrade ?? .primary1 },
                    set: { settings.targetGrade = $0 }
                )) {
                    ForEach(LearningGrade.allCases) { grade in
                        Text(settings.t(grade.title)).tag(grade)
                    }
                }
                .accessibilityIdentifier("settings.target-grade")
            }
            Section {
                Button { settings.applyPresentation(.cantonese) } label: {
                    Label(settings.t("粵語 · 繁體中文", "粤语 · 繁体中文"), systemImage: "speaker.wave.2")
                }
                .accessibilityIdentifier("presentation.cantonese")
                Button { settings.applyPresentation(.mandarin) } label: {
                    Label(settings.t("普通話 · 簡體中文", "普通话 · 简体中文"), systemImage: "speaker.wave.2")
                }
                .accessibilityIdentifier("presentation.mandarin")
            } header: {
                Text(settings.t("學習語言", "学习语言"))

            }
            Section {
                Picker(settings.t("文字", "文字"), selection: $settings.script) {
                    Text("繁體中文").tag(Script.hant)
                    Text("简体中文").tag(Script.hans)
                }
                Picker(settings.t("朗讀語言", "朗读语言"), selection: $settings.voice) {
                    Text(settings.t("粵語", "粤语")).tag(VoiceLanguage.cantonese)
                    Text(settings.t("普通話", "普通话")).tag(VoiceLanguage.mandarin)
                }
                if !speech.isCheckingVoices && !speech.hasVoice(for: settings.voice) {
                    Text(settings.t("所選聲音尚未就緒。請到系統設定的「輔助使用」下載對應語言聲音，再返回重新檢查。",
                                    "所选声音尚未就绪。请到系统设置的“辅助功能”下载对应语言声音，再返回重新检查。"))
                        .font(.footnote)
                        .foregroundStyle(Color.chestnut)
                }
            } header: {
                Text(settings.t("文字與朗讀", "文字与朗读"))

            }

            Section {
                ForEach(VoiceLanguage.allCases) { language in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language == .cantonese ? settings.t("粵語", "粤语") : settings.t("普通話", "普通话"))
                            Text(speech.voice(for: language)?.name ?? (speech.isCheckingVoices
                                ? settings.t("檢查中…", "检查中…") : settings.t("需要下載聲音", "需要下载声音")))
                                .font(.caption).foregroundStyle(Color.chestnut)
                        }
                        Spacer()
                        Button(settings.t("試聽", "试听")) {
                            let sample = language == .cantonese
                                ? "你好，我係貝貝。今日我哋一齊讀古詩。床前明月光，疑是地上霜。"
                                : "你好，我是贝贝。今天我们一起读古诗。床前明月光，疑是地上霜。"
                            speech.speak([("voice-preview", sample)], language: language)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!speech.hasVoice(for: language))
                        .accessibilityIdentifier("voice.preview.\(language.rawValue)")
                    }
                }
                Button(settings.t("重新檢查聲音", "重新检查声音")) { speech.refreshVoices() }
                    .disabled(speech.isCheckingVoices)
                if speech.isSpeaking {
                    Button(settings.t("停止試聽", "停止试听")) { speech.stop() }
                }
            } header: {
                Text(settings.t("朗讀試聽", "朗读试听"))

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
                Text(settings.t("內置 \(PoemLibrary.shared.poems.count) 首精講詩，支援離線學習。朗讀使用裝置的粵語／普通話聲音。",
                                "内置 \(PoemLibrary.shared.poems.count) 首精讲诗，支持离线学习。朗读使用设备的粤语／普通话声音。"))
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
                Text(settings.t("調整日期以展示跨日複習。", "调整日期以展示跨日复习。"))
            }
            #endif

            Section {
                Button(settings.t("清除學習記錄與作品", "清除学习记录与作品"), role: .destructive) {
                    confirmReset = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(settings.t("設定", "设置"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { speech.refreshVoices() }
        .onDisappear { speech.stop() }
        .confirmationDialog(settings.t("清除後，學習進度、收藏、錯題、遊戲記錄和我的詩集都會刪除，無法復原。", "清除后，学习进度、收藏、错题、游戏记录和我的诗集都会删除，无法恢复。"),
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button(settings.t("清除", "清除"), role: .destructive) {
                ProgressStore(context: context).resetAll()
            }
        }
    }
}
