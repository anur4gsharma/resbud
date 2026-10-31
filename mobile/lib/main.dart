import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'data/local_project_repository.dart';
import 'features/export/docx_export_client.dart';
import 'features/export/docx_file_saver.dart';
import 'features/generation/generation_api_client.dart';
import 'features/project_input/project_input_page.dart';
import 'import/source_document_importer.dart';
import 'shared/design_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final DatabaseFactory factory = kIsWeb ? databaseFactoryFfiWeb : databaseFactory;
  runApp(ResbudBootstrap(databaseFactory: factory));
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

class ResbudApp extends StatefulWidget {
  ResbudApp({
    super.key,
    required this.repository,
    PaperGenerationApi? generationApi,
    PaperExportApi? exportApi,
    DocxFileSaver? fileSaver,
    this.sourcePicker,
    this.initialThemeMode = ThemeMode.system,
  }) : generationApi = generationApi ?? GenerationApiClient.fromEnvironment(),
       exportApi = exportApi ?? DocxExportApiClient.fromEnvironment(),
       fileSaver = fileSaver ?? LocalDocxFileSaver();

  final LocalProjectRepository repository;
  final PaperGenerationApi generationApi;
  final PaperExportApi exportApi;
  final DocxFileSaver fileSaver;
  final SourcePicker? sourcePicker;
  final ThemeMode initialThemeMode;

  @override
  State<ResbudApp> createState() => _ResbudAppState();
}

class _ResbudAppState extends State<ResbudApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
  }

  void _toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.light) {
        _themeMode = ThemeMode.dark;
      } else if (_themeMode == ThemeMode.dark) {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light;
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Resbud',
    theme: ResbudDesignTokens.lightTheme(),
    darkTheme: ResbudDesignTokens.darkTheme(),
    themeMode: _themeMode,
    home: ProjectListPage(
      repository: widget.repository,
      generationApi: widget.generationApi,
      exportApi: widget.exportApi,
      fileSaver: widget.fileSaver,
      sourcePicker: widget.sourcePicker,
      currentThemeMode: _themeMode,
      onToggleTheme: _toggleTheme,
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
    this.currentThemeMode = ThemeMode.system,
    this.onToggleTheme,
  });

  final LocalProjectRepository repository;
  final PaperGenerationApi generationApi;
  final PaperExportApi exportApi;
  final DocxFileSaver fileSaver;
  final SourcePicker? sourcePicker;
  final ThemeMode currentThemeMode;
  final VoidCallback? onToggleTheme;

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  late Future<List<LocalProject>> _projects;
  bool _showGuide = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _projects = widget.repository.listProjects();
  }

  Future<void> _createProject() async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (_) => _NewProjectDialog(sourcePicker: widget.sourcePicker),
    );
    if (!mounted || result == null) return;
    final String title;
    final String description;
    final String sourceDraft;
    final bool isDocumentMode;
    if (result is _NewProjectResult) {
      title = result.title;
      description = result.description;
      sourceDraft = result.sourceDraft;
      isDocumentMode = result.isDocumentMode;
    } else if (result is String) {
      title = result;
      description = '';
      sourceDraft = '';
      isDocumentMode = false;
    } else {
      return;
    }
    if (title.trim().isEmpty) return;

    try {
      final project = await widget.repository.createProject(
        title: title,
        projectContext: {
          'description': description,
          'creation_mode': isDocumentMode ? 'document' : 'manual',
        },
        sourceDraft: sourceDraft,
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Resbud'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.primary.withAlpha(50)),
              ),
              child: Text(
                'Local-first',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('button-toggle-guide'),
            tooltip: _showGuide ? 'Hide guide' : 'Research guide',
            icon: Icon(_showGuide ? Icons.lightbulb : Icons.lightbulb_outline),
            onPressed: () => setState(() => _showGuide = !_showGuide),
          ),
          if (widget.onToggleTheme != null)
            IconButton(
              key: const ValueKey('button-toggle-theme'),
              tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
              icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              onPressed: widget.onToggleTheme,
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        icon: const Icon(Icons.add),
        label: const Text('New project'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: FutureBuilder<List<LocalProject>>(
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.description_outlined, size: 48, color: ResbudDesignTokens.seedColor),
                        const SizedBox(height: ResbudDesignTokens.contentSpacing),
                        Text(
                          'Your projects will appear here.',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
                        if (_showGuide) ...[
                          const SizedBox(height: 32),
                          _buildOnboardingGuide(theme),
                        ],
                      ],
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
                children: [
                  if (_showGuide) ...[
                    _buildOnboardingGuide(theme),
                    const SizedBox(height: 12),
                  ],
                  for (final project in projects)
                    _buildProjectCard(project, theme),
                  const SizedBox(height: 48),
                ],
              );
            },
          ),
        ),
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

  Widget _buildOnboardingGuide(ThemeData theme) => Card(
    key: const ValueKey('onboarding-guide-card'),
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    color: theme.colorScheme.primaryContainer.withAlpha(40),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: theme.colorScheme.primary.withAlpha(50)),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showPhilosophyGuide(theme),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.school_outlined, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Resbud Academic Writing Philosophy',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    'Strictly grounded in your notes · Zero hallucination · 100% Local SQLite',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
          ],
        ),
      ),
    ),
  );

  void _showPhilosophyGuide(ThemeData theme) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.school_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Research Integrity & Writing Philosophy')),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Resbud is built for serious academic writing where factual accuracy, provenance, and privacy are non-negotiable.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 16),
                _guideBullet(
                  theme,
                  Icons.verified_outlined,
                  'Strictly Non-Hallucinatory Grounding',
                  'Every claim, experiment, and reference must come from material you provide. If data is absent, Resbud explicitly notes it as unperformed or missing rather than inventing findings.',
                ),
                const SizedBox(height: 12),
                _guideBullet(
                  theme,
                  Icons.description_outlined,
                  'Two Input Workflows',
                  '• Document Mode: Upload raw lab notes, outline, or source text (.txt/.md). AI synthesizes the draft directly.\n• Structured Brief: Fill in field-by-field research question, methodology, objectives, and findings.',
                ),
                const SizedBox(height: 12),
                _guideBullet(
                  theme,
                  Icons.lock_outline,
                  'Zero Cloud Retention',
                  'Manuscripts, versions, and edits are stored strictly in local SQLite on your machine. API calls to LLM providers are stateless and ephemeral.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Widget _guideBullet(ThemeData theme, IconData icon, String title, String body) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: theme.colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text(body, style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
          ],
        ),
      ),
    ],
  );

  Widget _buildProjectCard(LocalProject project, ThemeData theme) {
    final projectContext = project.projectContext;
    final isDocMode = projectContext['creation_mode'] == 'document' ||
        (projectContext['description'] != null &&
            (projectContext['description'] as String).isNotEmpty &&
            (projectContext['research_question'] == null ||
                (projectContext['research_question'] as String).isEmpty));
    final researchField = projectContext['research_field'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDocMode
                ? Colors.blue.withAlpha(24)
                : theme.colorScheme.primary.withAlpha(24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isDocMode ? Icons.description_outlined : Icons.edit_note_outlined,
            color: isDocMode ? Colors.blue.shade700 : theme.colorScheme.primary,
            size: 22,
          ),
        ),
        title: Text(
          project.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Updated ${_dateLabel(project.updatedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (researchField != null && researchField.trim().isNotEmpty)
                Text(
                  researchField.trim(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isDocMode
                      ? Colors.blue.withAlpha(22)
                      : theme.colorScheme.secondaryContainer.withAlpha(60),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isDocMode ? 'Document Mode' : 'Structured',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDocMode ? Colors.blue.shade800 : theme.colorScheme.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
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
    );
  }
}

class _NewProjectResult {
  const _NewProjectResult({
    required this.title,
    this.description = '',
    this.sourceDraft = '',
    this.isDocumentMode = true,
  });

  final String title;
  final String description;
  final String sourceDraft;
  final bool isDocumentMode;
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({this.sourcePicker});

  final SourcePicker? sourcePicker;

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isDocumentMode = false;
  String _sourceDraft = '';
  String? _sourceFileName;
  bool _readingFile = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _readingFile = true);
    try {
      final picker = widget.sourcePicker;
      PickedSource? picked;
      if (picker != null) {
        picked = await picker();
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['txt', 'md', 'markdown', 'docx', 'pdf'],
        );
        if (result.isNotEmpty) {
          final file = result.single;
          picked = (name: file.name, bytes: await file.readAsBytes());
        }
      }
      if (picked != null) {
        final imported = const SourceDocumentImporter().importBytes(
          fileName: picked.name,
          bytes: picked.bytes,
          allowPdf: true,
        );
        setState(() {
          _sourceDraft = imported.text;
          _sourceFileName = picked!.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _readingFile = false);
    }
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      _NewProjectResult(
        title: title,
        description: _descriptionController.text.trim(),
        sourceDraft: _sourceDraft,
        isDocumentMode: _isDocumentMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New project'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Working title',
                hintText: 'e.g. Scalable Quantum Error Correction',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text(
              'How do you want to create your paper?',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: true,
                  label: Text('From File (.txt/.md)'),
                  icon: Icon(Icons.description_outlined),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Manual Form Details'),
                  icon: Icon(Icons.edit_note_outlined),
                ),
              ],
              selected: {_isDocumentMode},
              onSelectionChanged: (selected) => setState(() => _isDocumentMode = selected.first),
            ),
            if (_isDocumentMode) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Paper description',
                  hintText: 'What is this paper about? Focus, scope, and objectives...',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _sourceFileName != null
                          ? 'Attached: $_sourceFileName (${_sourceDraft.length} chars)'
                          : (_sourceDraft.isNotEmpty
                              ? 'Document loaded (${_sourceDraft.length} chars)'
                              : 'No document attached yet'),
                      style: TextStyle(
                        fontSize: 12,
                        color: _sourceDraft.isNotEmpty ? Colors.green.shade800 : Colors.grey.shade600,
                        fontWeight: _sourceDraft.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _readingFile ? null : _pickFile,
                    icon: _readingFile
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.attach_file, size: 16),
                    label: Text(_sourceDraft.isNotEmpty ? 'Replace file' : 'Attach file'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
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
