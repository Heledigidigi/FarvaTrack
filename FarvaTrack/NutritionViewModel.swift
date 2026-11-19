LibrarySyncService.shared.localChange(context: context, userID: userID)
deleteCustomFood içinde try? context.save() satırının altına:
        if let userID { LibrarySyncService.shared.localChange(context: context, userID: userID) }
toggleFavorite içinde try? context.save() satırının altına:
        LibrarySyncService.shared.localChange(context: context, userID: userID)