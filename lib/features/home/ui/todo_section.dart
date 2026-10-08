import 'package:material_ui/material_ui.dart';

import '../../../core/models/todo.dart';
import '../../../core/widgets/empty_state.dart';
import 'section_title.dart';
import 'todo_row.dart';

/// A titled list of todos with an empty state.
class TodoSection extends StatelessWidget {
  const TodoSection({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.todos,
    required this.onOpen,
    this.overdue = false,
  });

  final String title;
  final String emptyLabel;
  final List<Todo> todos;
  final ValueChanged<Todo> onOpen;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title),
        const SizedBox(height: 12),
        if (todos.isEmpty)
          AppEmptyState(emptyLabel)
        else
          for (final todo in todos)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TodoRow(
                todo: todo,
                overdue: overdue,
                onOpen: () => onOpen(todo),
              ),
            ),
      ],
    );
  }
}
