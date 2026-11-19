LibrarySyncService.shared.localChange(context: context, userID: userID)
deleteCustomExercise içinde, try context.save() bloğunun altına:

        if let userID { LibrarySyncService.shared.localChange(context: context, userID: userID) }