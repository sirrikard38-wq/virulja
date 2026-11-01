import 'i18n.dart';

/// What a trip's reminder says on [today], or null when no reminder is due.
String? reminderText(DateTime start, DateTime today) {
  switch (start.difference(today).inDays) {
    case 21:
      return tr('Još 3 tjedna do putovanja!');
    case 14:
      return tr('Još 2 tjedna do putovanja!');
    case 7:
      return tr('Još tjedan dana do putovanja!');
    case 3:
      return tr('Još 3 dana do putovanja!');
    case 2:
      return tr('Još 2 dana do putovanja!');
    case 1:
      return tr('Još 1 dan do putovanja!');
    default:
      return null;
  }
}
