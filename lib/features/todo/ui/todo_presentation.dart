import 'package:forui/forui.dart';

import '../../../core/models/todo.dart';

/// The [FBadge] variant that conveys [status].
FBadgeVariant statusVariant(TodoStatus status) => switch (status) {
  TodoStatus.todo => FBadgeVariant.secondary,
  TodoStatus.inProgress => FBadgeVariant.primary,
  TodoStatus.completed => FBadgeVariant.outline,
};

/// A human label for [status].
String statusLabel(TodoStatus status) => switch (status) {
  TodoStatus.todo => 'To do',
  TodoStatus.inProgress => 'In progress',
  TodoStatus.completed => 'Completed',
};

/// The [FBadge] variant that conveys [priority].
FBadgeVariant priorityVariant(TodoPriority priority) => switch (priority) {
  TodoPriority.high => FBadgeVariant.destructive,
  TodoPriority.medium => FBadgeVariant.primary,
  TodoPriority.low => FBadgeVariant.secondary,
};

/// A human label for [priority].
String priorityLabel(TodoPriority priority) => switch (priority) {
  TodoPriority.high => 'High',
  TodoPriority.medium => 'Medium',
  TodoPriority.low => 'Low',
};
