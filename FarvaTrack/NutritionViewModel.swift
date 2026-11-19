LibrarySyncService.shared.localChange(context: context, userID: userID)
deleteCustomFood içinde try? context.save() satırının altına:
        if let userID { LibrarySyncService.shared.localChange(context: context, userID: userID) }
toggleFavorite içinde try? context.save() satırının altına:
        LibrarySyncService.shared.localChange(context: context, userID: userID)
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
