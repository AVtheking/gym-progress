import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage("faceIDLock") private var lockEnabled = false
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderDay") private var reminderDay = 1
    @AppStorage("reminderSeconds") private var reminderSeconds = 9 * 3600.0
    @Query private var photos: [ProgressPhoto]
    @State private var notificationsDenied = false

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(reminderSeconds) },
            set: { reminderSeconds = $0.timeIntervalSince(Calendar.current.startOfDay(for: $0)) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Require Face ID", isOn: $lockEnabled)
                } footer: {
                    Text("Photos are stored only inside this app, never in your photo library.")
                }
                Section("Monthly reminder") {
                    Toggle("Remind me", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Stepper("Day \(reminderDay) of each month", value: $reminderDay, in: 1...28)
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
                Section {
                    LabeledContent("Photos", value: "\(photos.count)")
                }
            }
            .navigationTitle("Settings")
            .task(id: "\(reminderEnabled)-\(reminderDay)-\(reminderSeconds)") { await updateReminder() }
            .alert("Notifications are off", isPresented: $notificationsDenied) {
                Button("OK") {}
            } message: {
                Text("Allow notifications for this app in Settings to get monthly reminders.")
            }
        }
    }

    private func updateReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["monthly-photo"])
        guard reminderEnabled else { return }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            reminderEnabled = false
            notificationsDenied = true
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Progress photo day"
        content.body = "Take this month's front, side and back photos."
        var components = DateComponents()
        components.day = reminderDay
        components.hour = Int(reminderSeconds) / 3600
        components.minute = Int(reminderSeconds) % 3600 / 60
        try? await center.add(UNNotificationRequest(
            identifier: "monthly-photo",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }
}
