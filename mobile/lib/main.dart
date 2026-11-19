import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'data/auth_session_manager.dart';
import 'data/local_project_repository.dart';
import 'features/auth/auth_session_dialog.dart';
import 'features/export/docx_export_client.dart';
import 'features/export/docx_file_saver.dart';
import 'features/generation/generation_api_client.dart';
import 'features/generation/generation_models.dart';
import 'features/paper_editor/paper_editor_page.dart';
import 'features/project_input/project_input_page.dart';
import 'import/source_document_importer.dart';
import 'shared/design_tokens.dart';
import 'shared/widgets/resbud_status_badge.dart';

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
  AuthSessionManager? _authManager;

  @override
  void initState() {
    super.initState();
    _openRepository();
  }

  void _openRepository() {
    _repository = LocalProjectRepository.open(factory: widget.databaseFactory).then((repo) async {
      final manager = AuthSessionManager(repo);
      await manager.initialize();
      _authManager = manager;
      return repo;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LocalProjectRepository>(
    future: _repository,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ResbudApp(
          repository: snapshot.data!,
          authManager: _authManager ?? AuthSessionManager(snapshot.data!),
        );
      }
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
    AuthSessionManager? authManager,
    PaperGenerationApi? generationApi,
    PaperExportApi? exportApi,
    DocxFileSaver? fileSaver,
    this.sourcePicker,
    this.initialThemeMode = ThemeMode.system,
  }) : authManager = authManager ?? AuthSessionManager(repository),
       generationApi = generationApi ??
           GenerationApiClient.fromEnvironment(
             tokenProvider: (authManager ?? AuthSessionManager(repository)).getToken,
           ),
       exportApi = exportApi ??
           DocxExportApiClient.fromEnvironment(
             tokenProvider: (authManager ?? AuthSessionManager(repository)).getToken,
           ),
       fileSaver = fileSaver ?? LocalDocxFileSaver();

  final LocalProjectRepository repository;
  final AuthSessionManager authManager;
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
      authManager: widget.authManager,
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
  ProjectListPage({
    super.key,
    required this.repository,
    AuthSessionManager? authManager,
    required this.generationApi,
    required this.exportApi,
    required this.fileSaver,
    this.sourcePicker,
    this.currentThemeMode = ThemeMode.system,
    this.onToggleTheme,
  }) : authManager = authManager ?? AuthSessionManager(repository);

  final LocalProjectRepository repository;
  final AuthSessionManager authManager;
  final PaperGenerationApi generationApi;
  final PaperExportApi exportApi;
  final DocxFileSaver fileSaver;
  final SourcePicker? sourcePicker;
  final ThemeMode currentThemeMode;
  final VoidCallback? onToggleTheme;

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<List<LocalProject>> _projects;
  late Future<List<SavedManuscript>> _savedManuscripts;
  late Future<List<LocalProject>> _unfinishedProjects;
  bool _showGuide = true;
  bool _isExporting = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFormat = 'All';
  String _sortBy = 'date_desc';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant ProjectListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    _projects = widget.repository.listProjects();
    _savedManuscripts = widget.repository.listSavedManuscripts(
      search: _searchQuery,
      format: _selectedFormat == 'All' ? null : _selectedFormat,
      sortBy: _sortBy,
      onlyCurrent: true,
    );
    _unfinishedProjects = widget.repository.listUnfinishedProjects();
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
      isDocumentMode = true;
    } else {
      return;
    }
    if (title.trim().isEmpty) return;

    try {
      final figures = result is _NewProjectResult ? result.figures : const <Map<String, dynamic>>[];
      final project = await widget.repository.createProject(
        title: title,
        projectContext: {
          'description': description,
          'creation_mode': isDocumentMode ? 'document' : 'manual',
          if (figures.isNotEmpty) 'figures': figures,
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
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
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
        ),
        actions: [
          IconButton(
            key: const ValueKey('button-auth-settings'),
            tooltip: 'Backend & Authentication',
            icon: ListenableBuilder(
              listenable: widget.authManager,
              builder: (context, _) => Icon(
                widget.authManager.isValid ? Icons.cloud_done : Icons.cloud_queue,
                color: widget.authManager.isValid ? Colors.green : null,
              ),
            ),
            onPressed: () => AuthSessionDialog.show(context, widget.authManager),
          ),
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
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(key: ValueKey('tab-dashboard'), text: 'Dashboard'),
            Tab(key: ValueKey('tab-my-papers'), text: 'My Papers'),
            Tab(key: ValueKey('tab-projects'), text: 'Projects'),
          ],
        ),
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
            builder: (context, projectSnap) {
              if (projectSnap.hasError) {
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
              if (!projectSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final projects = projectSnap.data!;
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

              return FutureBuilder<List<SavedManuscript>>(
                future: _savedManuscripts,
                builder: (context, manuscriptSnap) {
                  final manuscripts = manuscriptSnap.data ?? [];

                  return FutureBuilder<List<LocalProject>>(
                    future: _unfinishedProjects,
                    builder: (context, unfinishedSnap) {
                      final unfinished = unfinishedSnap.data ?? [];

                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDashboardView(projects, manuscripts, unfinished, theme),
                          _buildMyPapersView(manuscripts, theme),
                          _buildProjectsView(projects, theme),
                        ],
                      );
                    },
                  );
                },
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

  Widget _buildDashboardView(
    List<LocalProject> projects,
    List<SavedManuscript> manuscripts,
    List<LocalProject> unfinished,
    ThemeData theme,
  ) {
    return ListView(
      padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
      children: [
        if (_showGuide) ...[
          _buildOnboardingGuide(theme),
          const SizedBox(height: 8),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ActionChip(
                avatar: const Icon(Icons.menu_book, size: 14, color: Colors.teal),
                label: Text('My Papers (${manuscripts.length})', style: const TextStyle(fontSize: 11)),
                onPressed: () => _tabController.animateTo(1),
              ),
              const SizedBox(width: 6),
              if (unfinished.isNotEmpty) ...[
                ActionChip(
                  avatar: Icon(Icons.pending_actions, size: 14, color: Colors.amber.shade800),
                  label: Text('Drafts (${unfinished.length})', style: const TextStyle(fontSize: 11)),
                  onPressed: () => _tabController.animateTo(1),
                ),
                const SizedBox(width: 6),
              ],
              ActionChip(
                avatar: const Icon(Icons.folder_outlined, size: 14, color: Colors.blue),
                label: Text('Projects (${projects.length})', style: const TextStyle(fontSize: 11)),
                onPressed: () => _tabController.animateTo(2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final project in projects)
          _buildProjectCard(project, theme),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildMyPapersView(List<SavedManuscript> manuscripts, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
      children: [
        Row(
          children: [
            const Icon(Icons.menu_book, color: ResbudDesignTokens.seedColor, size: 22),
            const SizedBox(width: 8),
            Text(
              'My Papers',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'All saved academic manuscripts, drafts, and version histories stored locally.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        // Search bar
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search papers by title or abstract...',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _refresh();
                      });
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val.trim();
              _refresh();
            });
          },
        ),
        const SizedBox(height: 8),
        // Filter chips and Sort row
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final fmt in ['All', 'IEEE Conference', 'Nature', 'ACM Standard', 'Academic Standard'])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(fmt, style: const TextStyle(fontSize: 11)),
                          selected: _selectedFormat == fmt,
                          onSelected: (sel) {
                            setState(() {
                              _selectedFormat = sel ? fmt : 'All';
                              _refresh();
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _sortBy,
              underline: const SizedBox.shrink(),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
              items: const [
                DropdownMenuItem(value: 'date_desc', child: Text('Newest')),
                DropdownMenuItem(value: 'date_asc', child: Text('Oldest')),
                DropdownMenuItem(value: 'title_asc', child: Text('A–Z')),
                DropdownMenuItem(value: 'title_desc', child: Text('Z–A')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _sortBy = val;
                    _refresh();
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${manuscripts.length} saved manuscript${manuscripts.length == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 11),
        ),
        const SizedBox(height: 8),
        if (manuscripts.isEmpty)
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(30),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_outlined, size: 40, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'No manuscripts matching "$_searchQuery".'
                        : 'No saved papers yet.',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'Try clearing the search query or changing format filters.'
                        : 'Generate a paper from one of your projects to build your library.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_searchQuery.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _selectedFormat = 'All';
                          _refresh();
                        });
                      },
                      child: const Text('Clear Filters'),
                    )
                  else
                    FilledButton.tonal(
                      onPressed: () => _tabController.animateTo(2),
                      child: const Text('View Projects'),
                    ),
                ],
              ),
            ),
          )
        else
          for (final m in manuscripts)
            _buildManuscriptCard(m, theme),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildProjectsView(List<LocalProject> projects, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
      children: [
        Row(
          children: [
            const Icon(Icons.folder_outlined, color: ResbudDesignTokens.seedColor, size: 22),
            const SizedBox(width: 8),
            Text(
              'Research Projects',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${projects.length} research initiative${projects.length == 1 ? '' : 's'} containing inputs, figures, and drafts.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final project in projects)
          _buildProjectCard(project, theme),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildManuscriptCard(SavedManuscript m, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top tag row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.teal.withAlpha(60)),
                  ),
                  child: Text(
                    m.paperFormat,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    m.citationStyle,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'v${m.versionNumber}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                ),
                const Spacer(),
                if (m.isUnfinishedDraft)
                  const ResbudStatusBadge(
                    label: 'Unfinished draft',
                    type: ResbudStatusType.unsaved,
                    icon: Icons.pending_outlined,
                  )
                else
                  const ResbudStatusBadge(
                    label: 'Saved',
                    type: ResbudStatusType.saved,
                    icon: Icons.check_circle_outline,
                  ),
                PopupMenuButton<String>(
                  key: ValueKey('paper-menu-${m.id}'),
                  tooltip: 'Manuscript options',
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (action) {
                    if (action == 'history') {
                      _showVersionHistorySheet(m);
                    } else if (action == 'docx') {
                      _exportManuscriptDocx(m);
                    } else if (action == 'pdf') {
                      _exportManuscriptPdf(m);
                    } else if (action == 'rename') {
                      _renameManuscript(m);
                    } else if (action == 'duplicate') {
                      _duplicateManuscript(m);
                    } else if (action == 'delete') {
                      _deleteManuscript(m);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'history',
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 16),
                          SizedBox(width: 8),
                          Text('Version history', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'docx',
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.download, size: 16),
                          SizedBox(width: 8),
                          Text('Export DOCX', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'pdf',
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.picture_as_pdf, size: 16),
                          SizedBox(width: 8),
                          Text('Export PDF', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Rename paper', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'duplicate',
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Duplicate', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete paper', style: TextStyle(fontSize: 12.5, color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Title
            InkWell(
              onTap: () => _openManuscript(m, PaperWorkspaceMode.document),
              child: Text(
                m.paperTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Metadata line
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                Text(
                  'Project: ${m.projectTitle}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  '· Modified ${_dateLabel(m.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (m.authorCount > 0)
                  Text(
                    '· ${m.authorCount} author${m.authorCount == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (m.sectionCount > 0)
                  Text(
                    '· ${m.sectionCount} sections',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (m.abstractSnippet.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                m.abstractSnippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 0.8,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            // Action buttons
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 30),
                  ),
                  icon: const Icon(Icons.article_outlined, size: 14),
                  label: const Text('Read DOCX', style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _openManuscript(m, PaperWorkspaceMode.document),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 30),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                  label: const Text('View PDF', style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _openManuscript(m, PaperWorkspaceMode.pdf),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 30),
                  ),
                  icon: const Icon(Icons.edit_note, size: 15),
                  label: Text(
                    m.isUnfinishedDraft ? 'Continue Draft' : 'Edit Manuscript',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () => _openManuscript(m, PaperWorkspaceMode.editor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openManuscript(SavedManuscript manuscript, PaperWorkspaceMode mode) async {
    final project = await widget.repository.getProject(manuscript.projectId);
    final version = await widget.repository.getCurrentPaperVersion(manuscript.projectId) ??
        (await widget.repository.listPaperVersions(manuscript.projectId))
            .where((v) => v.id == manuscript.id)
            .firstOrNull;
    if (!mounted || project == null || version == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PaperEditorPage(
          repository: widget.repository,
          generationApi: widget.generationApi,
          project: project,
          initialVersion: version,
          initialMode: mode,
          exportApi: widget.exportApi,
          fileSaver: widget.fileSaver,
        ),
      ),
    );
    if (mounted) setState(_refresh);
  }

  Future<void> _openManuscriptVersion(
    String projectId,
    PaperVersion version,
    PaperWorkspaceMode mode,
  ) async {
    final project = await widget.repository.getProject(projectId);
    if (!mounted || project == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PaperEditorPage(
          repository: widget.repository,
          generationApi: widget.generationApi,
          project: project,
          initialVersion: version,
          initialMode: mode,
          exportApi: widget.exportApi,
          fileSaver: widget.fileSaver,
        ),
      ),
    );
    if (mounted) setState(_refresh);
  }

  Future<void> _renameManuscript(SavedManuscript manuscript) async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (_) => _RenameProjectDialog(initialTitle: manuscript.paperTitle),
    );
    if (!mounted || newTitle == null || newTitle.trim().isEmpty || newTitle.trim() == manuscript.paperTitle) return;

    try {
      await widget.repository.renamePaper(
        projectId: manuscript.projectId,
        newTitle: newTitle.trim(),
        versionId: manuscript.id,
      );
      if (mounted) {
        setState(_refresh);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paper renamed to "${newTitle.trim()}".')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The paper could not be renamed. Please try again.')),
        );
      }
    }
  }

  Future<void> _duplicateManuscript(SavedManuscript manuscript) async {
    try {
      final newProj = await widget.repository.duplicatePaper(
        projectId: manuscript.projectId,
        versionId: manuscript.id,
      );
      if (mounted) {
        setState(_refresh);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicated manuscript into "${newProj.title}".')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to duplicate manuscript. Please try again.')),
        );
      }
    }
  }

  Future<void> _deleteManuscript(SavedManuscript manuscript) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this manuscript?'),
        content: const Text(
          'This permanently deletes all saved versions of this paper. The research project inputs and attached figures will remain saved.',
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
      await widget.repository.deletePaper(projectId: manuscript.projectId);
      if (mounted) {
        setState(_refresh);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manuscript deleted.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete manuscript. Please try again.')),
        );
      }
    }
  }

  Future<void> _showVersionHistorySheet(SavedManuscript manuscript) async {
    final versions = await widget.repository.listPaperVersions(manuscript.projectId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Version History',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Text(
                  manuscript.paperTitle,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: versions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final v = versions[i];
                      final isCurrent = v.id == manuscript.id;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: isCurrent ? Colors.teal : Colors.grey.shade400,
                          child: Text(
                            'v${v.versionNumber}',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text('Version ${v.versionNumber} ${isCurrent ? "(Current)" : ""}'),
                        subtitle: Text('${v.origin.name} · ${_dateLabel(v.createdAt)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openManuscriptVersion(manuscript.projectId, v, PaperWorkspaceMode.document);
                              },
                              child: const Text('Preview'),
                            ),
                            if (!isCurrent)
                              IconButton(
                                icon: const Icon(Icons.restore, size: 20),
                                tooltip: 'Restore this version',
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  await widget.repository.restorePaperVersion(
                                    projectId: manuscript.projectId,
                                    targetVersionId: v.id,
                                  );
                                  if (mounted) {
                                    setState(_refresh);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Restored version ${v.versionNumber} as new snapshot.')),
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportManuscriptDocx(SavedManuscript manuscript) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Exporting DOCX...')),
    );
    try {
      final draft = PaperDraftPayload.fromJson(manuscript.rawPaper);
      final response = await widget.exportApi.exportDocx(draft);
      final filename = '${manuscript.paperTitle.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}.docx';
      await widget.fileSaver.saveDocx(
        bytes: response.bytes,
        suggestedFilename: response.suggestedFilename.isNotEmpty ? response.suggestedFilename : filename,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved $filename successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export DOCX: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportManuscriptPdf(SavedManuscript manuscript) async {
    _openManuscript(manuscript, PaperWorkspaceMode.pdf);
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

  Future<void> _openProjectPaper(LocalProject project, PaperWorkspaceMode mode) async {
    final version = await widget.repository.getCurrentPaperVersion(project.id) ??
        (await widget.repository.listPaperVersions(project.id)).firstOrNull;
    if (!mounted || version == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PaperEditorPage(
          repository: widget.repository,
          generationApi: widget.generationApi,
          project: project,
          initialVersion: version,
          initialMode: mode,
          exportApi: widget.exportApi,
          fileSaver: widget.fileSaver,
        ),
      ),
    );
    if (mounted) setState(_refresh);
  }

  Widget _buildProjectCard(LocalProject project, ThemeData theme) {
    final projectContext = project.projectContext;
    final isDocMode = projectContext['creation_mode'] == 'document' ||
        (projectContext['description'] != null &&
            (projectContext['description'] as String).isNotEmpty &&
            (projectContext['research_question'] == null ||
                (projectContext['research_question'] as String).isEmpty));
    final researchField = projectContext['research_field'] as String?;
    final hasGeneratedPaper = project.currentPaperVersionId != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDocMode
                    ? Colors.blue.withAlpha(24)
                    : theme.colorScheme.primary.withAlpha(24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isDocMode ? Icons.description_outlined : Icons.edit_note_outlined,
                color: isDocMode ? Colors.blue.shade700 : theme.colorScheme.primary,
                size: 20,
              ),
            ),
            title: Text(
              project.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: -0.1,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    'Updated ${_dateLabel(project.updatedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (researchField != null && researchField.trim().isNotEmpty)
                    Text(
                      researchField.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
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
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: isDocMode ? Colors.blue.shade800 : theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                  if (hasGeneratedPaper)
                    const ResbudStatusBadge(
                      label: 'Draft Ready',
                      type: ResbudStatusType.saved,
                      icon: Icons.check_circle_outline,
                    ),
                ],
              ),
            ),
            trailing: PopupMenuButton<String>(
              key: ValueKey('project-menu-${project.id}'),
              tooltip: 'Project options',
              icon: const Icon(Icons.more_vert, size: 20),
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
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Rename', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                  ),
                ),
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
          if (hasGeneratedPaper) ...[
            Divider(
              height: 1,
              thickness: 0.8,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 30),
                    ),
                    icon: const Icon(Icons.article_outlined, size: 14),
                    label: const Text('Read DOCX', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _openProjectPaper(project, PaperWorkspaceMode.document),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 30),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                    label: const Text('View PDF', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _openProjectPaper(project, PaperWorkspaceMode.pdf),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 30),
                    ),
                    icon: const Icon(Icons.edit_note, size: 15),
                    label: const Text('Edit Manuscript', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _openProjectPaper(project, PaperWorkspaceMode.editor),
                  ),
                ],
              ),
            ),
          ],
        ],
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
    this.figures = const [],
  });

  final String title;
  final String description;
  final String sourceDraft;
  final bool isDocumentMode;
  final List<Map<String, dynamic>> figures;
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
  String _sourceDraft = '';
  String? _sourceFileName;
  List<Map<String, dynamic>> _attachedFigures = [];
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
          allowedExtensions: [
            'txt', 'md', 'markdown', 'docx', 'pdf',
            'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp',
          ],
        );
        if (result.isNotEmpty) {
          final file = result.single;
          picked = (name: file.name, bytes: await file.readAsBytes());
        }
      }
      if (picked != null) {
        final ext = picked.name.split('.').last.toLowerCase();
        final isImage = const {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'}.contains(ext);
        final imported = const SourceDocumentImporter().importBytes(
          fileName: picked.name,
          bytes: picked.bytes,
          allowPdf: true,
        );
        final figures = <Map<String, dynamic>>[];
        if (isImage) {
          final mediaType = switch (ext) {
            'jpg' || 'jpeg' => 'image/jpeg',
            'webp' => 'image/webp',
            'gif' => 'image/gif',
            'bmp' => 'image/bmp',
            _ => 'image/png',
          };
          final b64 = 'data:$mediaType;base64,${base64Encode(picked.bytes)}';
          final cleanName = picked.name
              .replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')
              .replaceAll(RegExp(r'[-_]'), ' ')
              .trim();
          final titleName = cleanName
              .split(' ')
              .where((w) => w.isNotEmpty)
              .map((w) => w[0].toUpperCase() + w.substring(1))
              .join(' ');
          figures.add({
            'id': 'fig_1',
            'name': picked.name,
            'caption': 'Figure 1: $titleName',
            'description': 'Visual research material: $titleName ($ext).',
            'base64': b64,
            'bytes': picked.bytes,
          });
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = titleName;
          }
        }
        setState(() {
          _sourceDraft = imported.text;
          _sourceFileName = picked!.name;
          _attachedFigures = figures;
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
        isDocumentMode: true,
        figures: _attachedFigures,
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
              'Attach research material (.txt, .md, .docx, .pdf, images)',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
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
