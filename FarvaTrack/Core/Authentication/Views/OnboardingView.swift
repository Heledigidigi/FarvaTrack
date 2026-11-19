ForEach(FitnessGoal.allCases.filter { $0 != .loseWeight || birthDate.yearsSinceNow >= 18 }) { option in
        if birthDate.yearsSinceNow < 18, goal == .loseWeight { goal = .maintain }
