ForEach(FitnessGoal.allCases.filter { $0 != .loseWeight || birthDate.yearsSinceNow >= 18 }) { option in
Ayrıca finish() başında, yaş 18'in altındayken seçili hedef .loseWeight kalmışsa korumak için şunu ekleyin:

        if birthDate.yearsSinceNow < 18, goal == .loseWeight { goal = .maintain }