import SwiftUI

/// Uygulama ile widget ortak depoyu paylaşamıyorsa (ör. App Group'u olmayan bir kurulum)
/// widget dokunuşları uygulamaya ulaşmaz; kullanıcıya bunu açıkça söyler.
struct WidgetSyncNotice: View {
    var body: some View {
        if !SharedStore.isSharedContainerAvailable {
            Label {
                Text("Bu kurulumda widget ile uygulama veri paylaşamıyor. Widget'tan eklenenler buraya gelmez; kayıtları uygulamadan ekle. Uygulamayı App Group destekleyen bir imzayla (ör. ücretli geliştirici hesabı ya da TestFlight) kurunca düzelir.")
                    .font(.footnote)
                    .foregroundStyle(Color.ftTextSecondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.ftWarning)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
