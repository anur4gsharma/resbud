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
