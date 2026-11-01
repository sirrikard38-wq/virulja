/// What a trip's reminder says on [today], or null when no reminder is due.
String? reminderText(DateTime start, DateTime today) {
  switch (start.difference(today).inDays) {
    case 21:
      return 'Još 3 tjedna do putovanja!';
    case 14:
      return 'Još 2 tjedna do putovanja!';
    case 7:
      return 'Još tjedan dana do putovanja!';
    case 3:
      return 'Još 3 dana do putovanja!';
    case 2:
      return 'Još 2 dana do putovanja!';
    case 1:
      return 'Još 1 dan do putovanja!';
    default:
      return null;
  }
}
