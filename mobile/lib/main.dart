import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'data/local_project_repository.dart';
import 'shared/design_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ResbudBootstrap(databaseFactory: databaseFactory));
}

class ResbudBootstrap extends StatefulWidget {
  const ResbudBootstrap({super.key, required this.databaseFactory});

  final DatabaseFactory databaseFactory;

  @override
  State<ResbudBootstrap> createState() => _ResbudBootstrapState();
}

class _ResbudBootstrapState extends State<ResbudBootstrap> {
  late Future<LocalProjectRepository> _repository;

  @override
  void initState() {
    super.initState();
    _openRepository();
  }

  void _openRepository() {
    _repository = LocalProjectRepository.open(factory: widget.databaseFactory);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LocalProjectRepository>(
    future: _repository,
    builder: (context, snapshot) {
      if (snapshot.hasData) return ResbudApp(repository: snapshot.data!);
      if (snapshot.hasError) {
        return MaterialApp(
          theme: ResbudDesignTokens.lightTheme(),
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Your local projects could not be opened.'),
                    const SizedBox(height: ResbudDesignTokens.contentSpacing),
                    FilledButton(
                      onPressed: () => setState(_openRepository),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return MaterialApp(
        theme: ResbudDesignTokens.lightTheme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    },
  );
}

class ResbudApp extends StatelessWidget {
  const ResbudApp({super.key, required this.repository});

  final LocalProjectRepository repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Resbud',
    theme: ResbudDesignTokens.lightTheme(),
    home: ProjectListPage(repository: repository),
  );
}

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key, required this.repository});

  final LocalProjectRepository repository;

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  late Future<List<LocalProject>> _projects;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _projects = widget.repository.listProjects();
  }

  Future<void> _createProject() async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _NewProjectDialog(),
    );
    if (!mounted || title == null || title.trim().isEmpty) return;

    try {
      final project = await widget.repository.createProject(
        title: title,
        projectContext: const {},
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProjectDetailPage(
            repository: widget.repository,
            project: project,
          ),
        ),
      );
      if (mounted) setState(_refresh);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The project could not be saved. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Resbud')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _createProject,
      icon: const Icon(Icons.add),
      label: const Text('New project'),
    ),
    body: FutureBuilder<List<LocalProject>>(
      future: _projects,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Projects could not be loaded. Try again.'),
          );
        }
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final projects = snapshot.data!;
        if (projects.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(ResbudDesignTokens.pagePadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 44),
                  SizedBox(height: ResbudDesignTokens.contentSpacing),
                  Text('Your projects will appear here.'),
                  SizedBox(height: 8),
                  Text(
                    'Create a project to start saving your research locally.',
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
          children: [
            for (final project in projects)
              Card(
                child: ListTile(
                  title: Text(project.title),
                  subtitle: Text('Updated ${_dateLabel(project.updatedAt)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ProjectDetailPage(
                          repository: widget.repository,
                          project: project,
                        ),
                      ),
                    );
                    if (mounted) setState(_refresh);
                  },
                ),
              ),
          ],
        );
      },
    ),
    bottomNavigationBar: const SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          'Projects stay on this device. There is no cloud backup; uninstalling the app may delete them.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final TextEditingController _titleController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New project'),
    content: TextField(
      controller: _titleController,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Working title'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _titleController.text),
        child: const Text('Create'),
      ),
    ],
  );
}

class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({
    super.key,
    required this.repository,
    required this.project,
  });

  final LocalProjectRepository repository;
  final LocalProject project;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _sourceController;
  late LocalProject _project;
  late Future<List<PaperVersion>> _versions;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _titleController = TextEditingController(text: _project.title);
    _sourceController = TextEditingController(text: _project.sourceDraft);
    _loadVersions();
  }

  void _loadVersions() {
    _versions = widget.repository.listPaperVersions(_project.id);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await widget.repository.updateProjectInputs(
        projectId: _project.id,
        title: _titleController.text,
        projectContext: _project.projectContext,
        sourceDraft: _sourceController.text,
      );
      if (!mounted) return;
      setState(() {
        _project = saved;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project saved on this device.')),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The project was not saved. Your previous saved version remains available.',
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this project?'),
        content: const Text(
          'This permanently deletes the project and its local version history. There is no cloud backup or recovery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteProject(_project.id);
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The project could not be deleted. Please try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Project'),
      actions: [
        IconButton(
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete project',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Working title'),
        ),
        const SizedBox(height: ResbudDesignTokens.contentSpacing),
        TextField(
          controller: _sourceController,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            labelText: 'Original research draft',
            hintText: 'Paste or import your source material in a later step.',
          ),
        ),
        const SizedBox(height: ResbudDesignTokens.contentSpacing),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save project'),
        ),
        const SizedBox(height: 28),
        Text('Saved versions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<PaperVersion>>(
          future: _versions,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return const Text('Version history could not be loaded.');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            if (snapshot.data!.isEmpty)
              return const Text('No paper versions saved yet.');
            return Column(
              children: [
                for (final version in snapshot.data!)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Version ${version.versionNumber}'),
                    subtitle: Text(
                      '${version.origin.name} · schema ${version.schemaVersion}',
                    ),
                    trailing: version.id == _project.currentPaperVersionId
                        ? const Icon(Icons.check_circle_outline)
                        : null,
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

String _dateLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
