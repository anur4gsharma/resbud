import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'data/local_project_repository.dart';
import 'features/export/docx_export_client.dart';
import 'features/export/docx_file_saver.dart';
import 'features/generation/generation_api_client.dart';
import 'features/project_input/project_input_page.dart';
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
  ResbudApp({
    super.key,
    required this.repository,
    PaperGenerationApi? generationApi,
    PaperExportApi? exportApi,
    DocxFileSaver? fileSaver,
    this.sourcePicker,
  }) : generationApi = generationApi ?? GenerationApiClient.fromEnvironment(),
       exportApi = exportApi ?? DocxExportApiClient.fromEnvironment(),
       fileSaver = fileSaver ?? LocalDocxFileSaver();

  final LocalProjectRepository repository;
  final PaperGenerationApi generationApi;
  final PaperExportApi exportApi;
  final DocxFileSaver fileSaver;
  final SourcePicker? sourcePicker;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Resbud',
    theme: ResbudDesignTokens.lightTheme(),
    home: ProjectListPage(
      repository: repository,
      generationApi: generationApi,
      exportApi: exportApi,
      fileSaver: fileSaver,
      sourcePicker: sourcePicker,
    ),
  );
}

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({
    super.key,
    required this.repository,
    required this.generationApi,
    required this.exportApi,
    required this.fileSaver,
    this.sourcePicker,
  });

  final LocalProjectRepository repository;
  final PaperGenerationApi generationApi;
  final PaperExportApi exportApi;
  final DocxFileSaver fileSaver;
  final SourcePicker? sourcePicker;

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
            generationApi: widget.generationApi,
            exportApi: widget.exportApi,
            fileSaver: widget.fileSaver,
            sourcePicker: widget.sourcePicker,
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

  Future<void> _renameProject(LocalProject project) async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (_) => _RenameProjectDialog(initialTitle: project.title),
    );
    if (!mounted || newTitle == null || newTitle.trim().isEmpty || newTitle.trim() == project.title) return;

    try {
      await widget.repository.updateProjectInputs(
        projectId: project.id,
        title: newTitle.trim(),
        projectContext: project.projectContext,
        sourceDraft: project.sourceDraft,
      );
      if (mounted) setState(_refresh);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The project could not be renamed. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _deleteProjectFromList(LocalProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this project?'),
        content: const Text(
          'This permanently deletes the project and its saved version history. There is no cloud backup or recovery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.repository.deleteProject(project.id);
      if (mounted) setState(_refresh);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The project could not be deleted. Please try again.'),
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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text('Projects could not be loaded. Try again.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => setState(_refresh),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final projects = snapshot.data!;
        if (projects.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.description_outlined, size: 48, color: ResbudDesignTokens.seedColor),
                  const SizedBox(height: ResbudDesignTokens.contentSpacing),
                  Text(
                    'Your projects will appear here.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create a project to start saving your research locally.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _createProject,
                    icon: const Icon(Icons.add),
                    label: const Text('Create your first project'),
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
                  title: Text(
                    project.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('Updated ${_dateLabel(project.updatedAt)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        key: ValueKey('project-menu-${project.id}'),
                        tooltip: 'Project options',
                        icon: const Icon(Icons.more_vert),
                        onSelected: (action) {
                          if (action == 'rename') {
                            _renameProject(project);
                          } else if (action == 'delete') {
                            _deleteProjectFromList(project);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 20),
                                SizedBox(width: 8),
                                Text('Rename'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ProjectDetailPage(
                          repository: widget.repository,
                          generationApi: widget.generationApi,
                          exportApi: widget.exportApi,
                          fileSaver: widget.fileSaver,
                          sourcePicker: widget.sourcePicker,
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

class _RenameProjectDialog extends StatefulWidget {
  const _RenameProjectDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<_RenameProjectDialog> {
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename project'),
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
        child: const Text('Rename'),
      ),
    ],
  );
}

class ProjectDetailPage extends StatelessWidget {
  const ProjectDetailPage({
    super.key,
    required this.repository,
    required this.generationApi,
    required this.project,
    this.exportApi,
    this.fileSaver,
    this.sourcePicker,
  });

  final LocalProjectRepository repository;
  final PaperGenerationApi generationApi;
  final LocalProject project;
  final PaperExportApi? exportApi;
  final DocxFileSaver? fileSaver;
  final SourcePicker? sourcePicker;

  @override
  Widget build(BuildContext context) =>
      ProjectInputPage(
        repository: repository,
        generationApi: generationApi,
        project: project,
        exportApi: exportApi,
        fileSaver: fileSaver,
        sourcePicker: sourcePicker,
      );
}

String _dateLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
