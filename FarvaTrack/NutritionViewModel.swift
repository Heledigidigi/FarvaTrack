func deleteCustomFood(...) {
    // mevcut kodlar
    try? context.save()

    if let userID {
        LibrarySyncService.shared.localChange(context: context, userID: userID)
    }
}
func toggleFavorite(...) {
    // mevcut kodlar
    try? context.save()

    LibrarySyncService.shared.localChange(context: context, userID: userID)
}
