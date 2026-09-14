import 'package:intl/intl.dart';

abstract final class DateFormats {
  static final time = DateFormat('h:mm a');
  static final date = DateFormat('MMMM d, yyyy');
  static final dateShort = DateFormat('MMM d, yyyy');
  static final shiftHeader = DateFormat('MMMM d, yyyy');
  static final dayKey = DateFormat('yyyy-MM-dd');

  static String timeRange(DateTime start, DateTime end) {
    return '${time.format(start)} - ${time.format(end)}';
  }
}
