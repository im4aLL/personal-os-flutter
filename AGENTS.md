# AGENTS

## Testing

- Do not write or add unit tests.
  Hadi verifies behavior manually.
- Do not recreate the `test/` directory or test files unless explicitly asked.

## UI components

- Use Forui widgets (`package:forui/forui.dart`) as-is for all UI.
- Do not create your own component when Forui already provides one.
  For example, use `FBadge` instead of a custom pill, `FButton` instead of a custom button, and `FCard` instead of a custom bordered container.
- Prefer a Forui component's built-in variants over custom styling that reimplements it.
  For example, use `FBadge(variant: .destructive, child: Text('High'))` rather than hand-rolling the badge decoration.
- If Forui does not provide the component you need, it is okay to build your own.
