import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/todo.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/centered_message.dart';
import '../../../core/widgets/padded_card.dart';
import '../providers/todo_providers.dart';
import 'todo_presentation.dart';

/// Read-only single-todo page opened from the Home dashboard.
///
/// Completing a todo happens here rather than from the Home list so a tap on
/// the dashboard only navigates and can never change state.
class TodoDetailPage extends ConsumerWidget {
  const TodoDetailPage({required this.todoId, super.key});

  /// The id of the todo to display.
  final String todoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTodo = ref.watch(todoByIdProvider(todoId));

    return FScaffold(
      header: FHeader.nested(
        prefixes: [
          FHeaderAction(
            icon: const Icon(Icons.arrow_back),
            onPress: () => Navigator.maybePop(context),
          ),
        ],
        title: const Text('Todo'),
      ),
      child: asyncTodo.when(
        data: (todo) => todo == null
            ? const CenteredMessage('This todo no longer exists.')
            : _TodoDetail(todo: todo),
        error: (_, _) => const CenteredMessage('Could not load this todo.'),
        loading: () => const Center(child: FCircularProgress()),
      ),
    );
  }
}

/// The loaded todo: status, title, metadata, description, and the complete
/// action.
class _TodoDetail extends ConsumerWidget {
  const _TodoDetail({required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final completed = todo.status == TodoStatus.completed;
    final dueDate = todo.dueDate;
    final overdue =
        !completed && dueDate != null && dueDate.compareTo(todayDate()) < 0;

    void setStatus(TodoStatus status) =>
        unawaited(ref.read(todoRepositoryProvider).setStatus(todo.id, status));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FBadge(
              variant: statusVariant(todo.status),
              child: Text(statusLabel(todo.status)),
            ),
            if (todo.priority != null)
              FBadge(
                variant: priorityVariant(todo.priority!),
                child: Text(priorityLabel(todo.priority!)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          todo.title,
          style: context.theme.typography.display.sm.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        FCard(
          builder: paddedCardBuilder,
          child: Column(
            spacing: 8,
            children: [
              _MetaRow(
                label: 'Due',
                value: dueDate == null ? 'None' : formatDateShort(dueDate),
                tone: overdue ? colors.error : null,
              ),
              _MetaRow(
                label: 'Created',
                value: formatDateTimeShort(todo.createdAt),
              ),
              _MetaRow(
                label: 'Updated',
                value: formatDateTimeShort(todo.updatedAt),
              ),
            ],
          ),
        ),
        if (todo.description != null &&
            todo.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle('Description'),
          const SizedBox(height: 8),
          FCard(
            builder: paddedCardBuilder,
            child: Text(
              todo.description!,
              style: context.theme.typography.body.sm,
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (completed)
          FButton(
            variant: .outline,
            onPress: () => setStatus(TodoStatus.todo),
            child: const Text('Reopen'),
          )
        else
          FButton(
            onPress: () => setStatus(TodoStatus.completed),
            child: const Text('Mark as done'),
          ),
      ],
    );
  }
}

/// A label/value metadata row.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      children: [
        Text(
          label,
          style: context.theme.typography.body.sm.copyWith(
            color: colors.mutedForeground,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: context.theme.typography.body.sm.copyWith(
              color: tone,
              fontWeight: tone == null ? null : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// A bold section heading.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: context.theme.typography.body.lg.copyWith(
      fontWeight: FontWeight.w600,
    ),
  );
}
