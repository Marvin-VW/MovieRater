import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/localization/app_strings.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/data/database_helper.dart';
import '../../settings/pages/settings_page.dart';
import '../models/movie.dart';
import '../services/movie_metadata_service.dart';

class AddMoviePage extends StatefulWidget {
  final Movie? existingMovie;
  final String? initialTitle;
  final String? initialYear;
  final String? initialPosterUrl;
  final MovieMetadata? initialMetadata;
  final String? initialImdbId;

  const AddMoviePage({
    super.key,
    this.existingMovie,
    this.initialTitle,
    this.initialYear,
    this.initialPosterUrl,
    this.initialMetadata,
    this.initialImdbId,
  });

  @override
  State<AddMoviePage> createState() => _AddMoviePageState();
}

class _AddMoviePageState extends State<AddMoviePage> {
  final _titleController = TextEditingController();
  final _commentController = TextEditingController();
  final _yearController = TextEditingController();
  final _genreController = TextEditingController();
  final _directorController = TextEditingController();
  final _runtimeController = TextEditingController();
  final _platformController = TextEditingController();
  final _imdbController = TextEditingController();
  final _rottenController = TextEditingController();

  double _rating = 2.5;
  File? _selectedImage;
  String _posterUrl = '';
  String _imdbId = '';
  bool _isFetchingMetadata = false;
  String? _metadataError;
  Timer? _titleDebounce;
  String _lastFetchedTitle = '';
  int _editorTabIndex = 0;

  @override
  void initState() {
    super.initState();

    final movie = widget.existingMovie;
    if (movie != null) {
      _titleController.text = movie.title;
      _commentController.text = movie.comment;
      _yearController.text = movie.year;
      _genreController.text = movie.genre;
      _directorController.text = movie.director;
      _runtimeController.text = movie.runtime;
      _platformController.text = movie.watchPlatform;
      _rating = movie.rating;
      _posterUrl = movie.posterUrl;
      _rottenController.text = movie.rottenTomatoesRating;
      _imdbId = movie.imdbId;
      if (movie.imdbRating != null) {
        _imdbController.text = movie.imdbRating!.toStringAsFixed(1);
      }

      if (movie.imagePath.isNotEmpty) {
        final imageFile = File(movie.imagePath);
        if (imageFile.existsSync()) {
          _selectedImage = imageFile;
        }
      }
    } else {
      _applyInitialSuggestion();
    }

    _titleController.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _commentController.dispose();
    _yearController.dispose();
    _genreController.dispose();
    _directorController.dispose();
    _runtimeController.dispose();
    _platformController.dispose();
    _imdbController.dispose();
    _rottenController.dispose();
    super.dispose();
  }

  void _applyInitialSuggestion() {
    final initialTitle = widget.initialTitle?.trim() ?? '';
    final initialYear = widget.initialYear?.trim() ?? '';
    final initialPoster = widget.initialPosterUrl?.trim() ?? '';
    final metadata = widget.initialMetadata;

    if (initialTitle.isNotEmpty) {
      _titleController.text = initialTitle;
      _lastFetchedTitle = initialTitle;
    }
    if (initialYear.isNotEmpty) {
      _yearController.text = initialYear;
    }
    if (initialPoster.isNotEmpty) {
      _posterUrl = initialPoster;
    }
    _imdbId = widget.initialImdbId?.trim() ?? '';
    if (metadata == null) return;

    _fillController(_yearController, metadata.year, true);
    _fillController(_genreController, metadata.genre, true);
    _fillController(_directorController, metadata.director, true);
    _fillController(_runtimeController, metadata.runtime, true);
    _fillController(_commentController, metadata.plot, true);

    if (metadata.posterUrl != null && _posterUrl.isEmpty) {
      _posterUrl = metadata.posterUrl!;
    }
    if ((metadata.imdbId ?? '').isNotEmpty) {
      _imdbId = metadata.imdbId!;
    }
    if (metadata.imdbRating != null) {
      _imdbController.text = metadata.imdbRating!.toStringAsFixed(1);
    }
    if (metadata.rottenTomatoesRating != null) {
      _rottenController.text = metadata.rottenTomatoesRating!;
    }
  }

  void _onTitleChanged() {
    final settings = AppSettingsScope.of(context);
    if (!settings.autoMetadataEnabled) return;

    final title = _titleController.text.trim();
    if (title.length < 2 || title == _lastFetchedTitle) return;

    _titleDebounce?.cancel();
    _titleDebounce = Timer(const Duration(milliseconds: 700), () {
      _loadMetadata(userInitiated: false);
    });
  }

  Future<void> _loadMetadata({required bool userInitiated}) async {
    final settings = AppSettingsScope.of(context);
    if (!userInitiated && !settings.autoMetadataEnabled) return;

    final title = _titleController.text.trim();
    final omdbApiKey = settings.omdbApiKey.trim();
    final tmdbApiKey = settings.tmdbApiKey.trim();
    if (title.isEmpty) return;

    if (omdbApiKey.isEmpty && tmdbApiKey.isEmpty) {
      setState(() {
        _metadataError = AppStrings.text(context, 'metadata_missing_api_key');
      });
      return;
    }

    if (omdbApiKey.isEmpty && tmdbApiKey.isNotEmpty) {
      setState(() {
        _isFetchingMetadata = true;
        _metadataError = null;
      });

      final tmdbPoster = await MovieMetadataService.fetchPosterFromTmdb(
        title,
        apiKey: tmdbApiKey,
      );
      if (!mounted) return;

      setState(() {
        _isFetchingMetadata = false;
        if (tmdbPoster != null) {
          _posterUrl = tmdbPoster;
          _metadataError = AppStrings.text(
            context,
            'metadata_tmdb_poster_only',
          );
        } else {
          _metadataError = AppStrings.text(context, 'metadata_error');
        }
      });
      return;
    }

    final shouldUpdateExternalRatings = settings.externalRatingsEnabled;

    setState(() {
      _isFetchingMetadata = true;
      if (userInitiated) {
        _metadataError = null;
      }
    });

    MovieSearchResult? selectedMovie;
    final candidates = await MovieMetadataService.searchMovies(
      title,
      omdbApiKey: omdbApiKey,
    );
    if (!mounted) return;

    if (candidates.isNotEmpty) {
      if (userInitiated && candidates.length > 1) {
        selectedMovie = await _pickMovieCandidate(candidates);
        if (!mounted) return;
        if (selectedMovie == null) {
          setState(() {
            _isFetchingMetadata = false;
          });
          return;
        }
      } else {
        selectedMovie = _bestMovieCandidate(title, candidates);
      }
    }

    final metadata = selectedMovie == null
        ? await MovieMetadataService.fetchMovieMetadata(
            title,
            omdbApiKey: omdbApiKey,
            tmdbApiKey: tmdbApiKey,
          )
        : await MovieMetadataService.fetchMovieMetadataByImdbId(
            selectedMovie.imdbId,
            omdbApiKey: omdbApiKey,
            tmdbApiKey: tmdbApiKey,
          );
    if (!mounted) return;

    if (metadata == null) {
      setState(() {
        _isFetchingMetadata = false;
        if (userInitiated) {
          _metadataError = AppStrings.text(context, 'metadata_error');
        }
      });
      return;
    }

    setState(() {
      _isFetchingMetadata = false;
      _metadataError = null;
      if (selectedMovie != null && userInitiated) {
        _lastFetchedTitle = selectedMovie.title;
        _titleController.text = selectedMovie.title;
        _imdbId = selectedMovie.imdbId;
      } else {
        _lastFetchedTitle = _titleController.text.trim();
        _imdbId = metadata.imdbId ?? _imdbId;
      }

      if (metadata.posterUrl != null && (_posterUrl.isEmpty || userInitiated)) {
        _posterUrl = metadata.posterUrl!;
      }

      _fillController(_yearController, metadata.year, userInitiated);
      _fillController(_genreController, metadata.genre, userInitiated);
      _fillController(_directorController, metadata.director, userInitiated);
      _fillController(_runtimeController, metadata.runtime, userInitiated);
      _fillController(_commentController, metadata.plot, userInitiated);

      if (shouldUpdateExternalRatings) {
        if (metadata.imdbRating != null &&
            (userInitiated || _imdbController.text.trim().isEmpty)) {
          _imdbController.text = metadata.imdbRating!.toStringAsFixed(1);
        }
        if (metadata.rottenTomatoesRating != null &&
            (userInitiated || _rottenController.text.trim().isEmpty)) {
          _rottenController.text = metadata.rottenTomatoesRating!;
        }
      }
    });
  }

  void _fillController(
    TextEditingController controller,
    String? incoming,
    bool userInitiated,
  ) {
    if (incoming == null || incoming.isEmpty) return;
    if (userInitiated || controller.text.trim().isEmpty) {
      controller.text = incoming;
    }
  }

  MovieSearchResult _bestMovieCandidate(
    String query,
    List<MovieSearchResult> candidates,
  ) {
    final normalizedQuery = _normalizeTitle(query);
    MovieSearchResult best = candidates.first;
    var bestScore = -1;

    for (final candidate in candidates) {
      final score = _candidateScore(normalizedQuery, candidate);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }

    return best;
  }

  int _candidateScore(String normalizedQuery, MovieSearchResult candidate) {
    final normalizedTitle = _normalizeTitle(candidate.title);
    var score = 0;

    if (normalizedTitle == normalizedQuery) score += 100;
    if (normalizedTitle == 'the$normalizedQuery') score += 80;
    if (normalizedTitle.startsWith(normalizedQuery)) score += 60;
    if (normalizedTitle.contains(normalizedQuery)) score += 30;

    if (candidate.year.startsWith('20')) {
      score += 3;
    } else if (candidate.year.startsWith('19')) {
      score += 1;
    }

    return score;
  }

  String _normalizeTitle(String value) {
    return value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  }

  Future<MovieSearchResult?> _pickMovieCandidate(
    List<MovieSearchResult> candidates,
  ) async {
    String t(String key) => AppStrings.text(context, key);

    return showModalBottomSheet<MovieSearchResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.72;
        return SafeArea(
          child: SizedBox(
            height: maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('metadata_pick_title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t('metadata_pick_desc'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final candidate = candidates[index];
                      return ListTile(
                        onTap: () => Navigator.pop(context, candidate),
                        leading: candidate.posterUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  candidate.posterUrl!,
                                  width: 34,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.movie_outlined),
                                ),
                              )
                            : const Icon(Icons.movie_outlined),
                        title: Text(candidate.title),
                        subtitle: Text(
                          '${candidate.year} · ${candidate.imdbId}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t('cancel')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 5, ratioY: 7),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Bild zuschneiden',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Bild zuschneiden', aspectRatioLockEnabled: true),
      ],
    );
    if (cropped == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(cropped.path);
    final savedPath = p.join(dir.path, fileName);
    final savedImage = await File(cropped.path).copy(savedPath);

    setState(() {
      _selectedImage = savedImage;
    });
  }

  Future<void> _saveMovie() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final year = _yearController.text.trim();
    final imdbId = _imdbId.trim();
    final isDuplicate = await DatabaseHelper.movieExists(
      imdbId: imdbId.isEmpty ? null : imdbId,
      title: title,
      year: year,
      excludeId: widget.existingMovie?.id,
    );
    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.text(context, 'movie_duplicate_error')),
        ),
      );
      return;
    }

    final imdbText = _imdbController.text.trim();
    final imdbValue = imdbText.isEmpty
        ? null
        : double.tryParse(imdbText.replaceAll(',', '.'));

    final movie = Movie(
      id: widget.existingMovie?.id,
      title: title,
      rating: _rating,
      comment: _commentController.text.trim(),
      imagePath: _selectedImage?.path ?? widget.existingMovie?.imagePath ?? '',
      posterUrl: _posterUrl,
      year: year,
      genre: _genreController.text.trim(),
      director: _directorController.text.trim(),
      runtime: _runtimeController.text.trim(),
      watchedAt: DateTime.now().toIso8601String(),
      watchPlatform: _platformController.text.trim(),
      imdbRating: imdbValue,
      rottenTomatoesRating: _rottenController.text.trim(),
      imdbId: imdbId,
      category: widget.existingMovie?.category ?? '',
    );

    await DatabaseHelper.saveMovie(movie);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.text(context, 'movie_saved'))),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingMovie == null ? t('add_movie') : t('edit_movie'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            context,
            title: t('auto_data'),
            child: _buildPosterHeader(context, t),
          ),
          const SizedBox(height: 12),
          _buildEditorTabs(context, t),
          const SizedBox(height: 12),
          _buildEditorContent(context, t),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saveMovie,
            icon: const Icon(Icons.save),
            label: Text(t('save')),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPosterHeader(
    BuildContext context,
    String Function(String key) t,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _posterPreview(context, t),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(t('choose_image')),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _isFetchingMetadata
                    ? null
                    : () => _loadMetadata(userInitiated: true),
                icon: _isFetchingMetadata
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(t('update_metadata')),
              ),
              const SizedBox(height: 8),
              Text(
                _isFetchingMetadata
                    ? t('metadata_loading')
                    : (_metadataError ?? t('metadata_hint')),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_metadataError == t('metadata_missing_api_key'))
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                    if (mounted) {
                      setState(() {
                        _metadataError = null;
                      });
                    }
                  },
                  child: Text(t('settings')),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditorTabs(BuildContext context, String Function(String key) t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SegmentedButton<int>(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        segments: [
          ButtonSegment(
            value: 0,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(t('editor_tab_auto')),
          ),
          ButtonSegment(
            value: 1,
            icon: const Icon(Icons.star_outline_rounded),
            label: Text(t('editor_tab_rating')),
          ),
          ButtonSegment(
            value: 2,
            icon: const Icon(Icons.checklist_rounded),
            label: Text(t('editor_tab_entry')),
          ),
        ],
        selected: {_editorTabIndex},
        onSelectionChanged: (selection) {
          setState(() {
            _editorTabIndex = selection.first;
          });
        },
      ),
    );
  }

  Widget _buildEditorContent(
    BuildContext context,
    String Function(String key) t,
  ) {
    switch (_editorTabIndex) {
      case 1:
        return _sectionCard(
          context,
          title: t('rating_details_title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('personal_rating'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _ratingBar(),
            ],
          ),
        );
      case 2:
        return _sectionCard(
          context,
          title: t('entry_details_title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _platformController,
                decoration: InputDecoration(labelText: t('watch_platform')),
              ),
              const SizedBox(height: 10),
              Text(
                t('rated_on_save_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      case 0:
      default:
        return _sectionCard(
          context,
          title: t('add_details_title'),
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: t('title'),
                  suffixIcon: IconButton(
                    onPressed: _isFetchingMetadata
                        ? null
                        : () => _loadMetadata(userInitiated: true),
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _yearController,
                      decoration: InputDecoration(labelText: t('year')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _runtimeController,
                      decoration: InputDecoration(labelText: t('runtime')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _genreController,
                decoration: InputDecoration(labelText: t('genre')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _directorController,
                decoration: InputDecoration(labelText: t('director')),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _imdbController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(labelText: t('imdb_rating')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _rottenController,
                      decoration: InputDecoration(
                        labelText: t('rotten_tomatoes'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                maxLines: null,
                maxLength: 800,
                controller: _commentController,
                decoration: InputDecoration(labelText: t('plot')),
              ),
            ],
          ),
        );
    }
  }

  Widget _posterPreview(BuildContext context, String Function(String key) t) {
    Widget child;

    if (_selectedImage != null && _selectedImage!.existsSync()) {
      child = Image.file(_selectedImage!, fit: BoxFit.cover);
    } else if (_posterUrl.isNotEmpty) {
      child = Image.network(
        _posterUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return _emptyPoster(context, t('no_image'));
        },
      );
    } else {
      child = _emptyPoster(context, t('no_image'));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 132,
        height: 188,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: child,
        ),
      ),
    );
  }

  Widget _emptyPoster(BuildContext context, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_creation_outlined,
            size: 30,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _ratingBar() {
    return RatingBar.builder(
      initialRating: _rating,
      minRating: 0,
      direction: Axis.horizontal,
      allowHalfRating: true,
      unratedColor: Colors.amber.withValues(alpha: 0.25),
      itemCount: 5,
      itemSize: 34,
      itemPadding: const EdgeInsets.symmetric(horizontal: 2),
      itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber),
      onRatingUpdate: (rating) {
        setState(() {
          _rating = rating;
        });
      },
      updateOnDrag: true,
    );
  }
}
