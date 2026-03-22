import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/localization/app_strings.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/data/database_helper.dart';
import '../../settings/pages/settings_page.dart';
import '../models/movie.dart';
import '../services/movie_metadata_service.dart';
import 'add_movie_page.dart';

class MovieListPage extends StatefulWidget {
  const MovieListPage({super.key});

  @override
  State<MovieListPage> createState() => _MovieListPageState();
}

class _MovieListPageState extends State<MovieListPage>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _watchedSearchController = TextEditingController();

  late final TabController _tabController;

  List<Movie> _movies = [];
  List<MovieSearchResult> _searchResults = [];
  List<DiscoverMovie> _discoverMovies = [];
  MovieSortField _sortField = MovieSortField.rating;
  SortDirection _sortDirection = SortDirection.desc;
  int _currentTab = 0;

  String? _selectedGenre;
  String? _selectedCategory;
  String _watchedSearchQuery = '';
  bool _isSearching = false;
  bool _isLoadingDiscover = false;
  String? _addingImdbId;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadMovies();
    _loadDiscoverMovies();
    _searchController.addListener(_onSearchChanged);
    _watchedSearchController.addListener(_onWatchedSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _watchedSearchController.removeListener(_onWatchedSearchChanged);
    _watchedSearchController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final nextTab = _tabController.index;
    if (!mounted || _currentTab == nextTab) return;
    setState(() {
      _currentTab = nextTab;
    });
    if (_currentTab == 2 && _discoverMovies.isEmpty) {
      _loadDiscoverMovies();
    }
  }

  void _onWatchedSearchChanged() {
    final next = _watchedSearchController.text.trim();
    if (_watchedSearchQuery == next) return;
    setState(() {
      _watchedSearchQuery = next;
    });
  }

  List<String> get _availableGenres {
    final genres = <String>{};
    for (final movie in _movies) {
      final raw = movie.genre.trim();
      if (raw.isEmpty) continue;
      for (final value in raw.split(',')) {
        final genre = value.trim();
        if (genre.isNotEmpty) {
          genres.add(genre);
        }
      }
    }
    final sorted = genres.toList()..sort((a, b) => a.compareTo(b));
    return sorted;
  }

  List<String> _defaultCategories(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    return [
      t('category_wishlist'),
      t('category_favorite'),
      t('category_rewatch'),
    ];
  }

  List<String> _availableCategories(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final categories = <String>{
      ..._defaultCategories(context),
      ...settings.customCategories,
    };

    for (final movie in _movies) {
      final category = movie.category.trim();
      if (category.isNotEmpty) {
        categories.add(category);
      }
    }

    final sorted = categories.toList()..sort((a, b) => a.compareTo(b));
    return sorted;
  }

  List<Movie> _filteredMovies(BuildContext context) {
    final query = _watchedSearchQuery.toLowerCase();

    return _movies.where((movie) {
      final title = movie.title.toLowerCase();
      if (query.isNotEmpty && !title.contains(query)) {
        return false;
      }

      if (_selectedGenre != null && _selectedGenre!.isNotEmpty) {
        final selected = _selectedGenre!.toLowerCase();
        final genres = movie.genre
            .toLowerCase()
            .split(',')
            .map((g) => g.trim())
            .toList();
        if (!genres.contains(selected)) {
          return false;
        }
      }

      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        if (movie.category.toLowerCase() != _selectedCategory!.toLowerCase()) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Future<void> _loadMovies() async {
    await DatabaseHelper.initDb();
    final movies = await DatabaseHelper.loadMovies(
      sortField: _sortField,
      direction: _sortDirection,
    );

    if (!mounted) return;
    setState(() {
      _movies = movies;
    });
  }

  Future<void> _addMovie() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddMoviePage()),
    );
    if (result == true) {
      _loadMovies();
    }
  }

  Future<void> _editMovie(Movie movie) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddMoviePage(existingMovie: movie)),
    );
    if (result == true) {
      _loadMovies();
    }
  }

  Future<void> _deleteMovie(int id) async {
    String t(String key) => AppStrings.text(context, key);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t('delete_confirm_title')),
          content: Text(t('delete_confirm_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('cancel')),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('confirm_delete')),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await DatabaseHelper.deleteMovie(id);
    _loadMovies();
  }

  Future<void> _loadDiscoverMovies() async {
    final settings = AppSettingsScope.of(context);
    final tmdbApiKey = settings.tmdbApiKey.trim();

    if (tmdbApiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _discoverMovies = [];
        _isLoadingDiscover = false;
      });
      return;
    }

    setState(() {
      _isLoadingDiscover = true;
    });

    List<DiscoverMovie> movies = const [];
    try {
      movies = await MovieMetadataService.discoverMovies(
        tmdbApiKey: tmdbApiKey,
      );
    } catch (_) {
      movies = const [];
    }

    if (!mounted) return;
    setState(() {
      _isLoadingDiscover = false;
      _discoverMovies = movies;
    });
  }

  bool _isResultAlreadyAdded(MovieSearchResult result) {
    final imdbId = result.imdbId.trim();
    final title = result.title.toLowerCase();
    final year = result.year.trim();

    return _movies.any((movie) {
      if (imdbId.isNotEmpty && movie.imdbId == imdbId) {
        return true;
      }

      if (movie.title.toLowerCase() != title) {
        return false;
      }

      final movieYear = movie.year.trim();
      if (year.isEmpty || movieYear.isEmpty) {
        return true;
      }
      return movieYear == year;
    });
  }

  bool _isTmdbSuggestionAlreadyAdded(TmdbMovieDetails details) {
    final imdbId = details.imdbId.trim();
    if (imdbId.isNotEmpty) {
      return _movies.any((movie) => movie.imdbId == imdbId);
    }

    return _movies.any((movie) {
      if (movie.title.toLowerCase() != details.title.toLowerCase()) {
        return false;
      }
      final year = movie.year.trim();
      if (details.year.isEmpty || year.isEmpty) {
        return true;
      }
      return year == details.year;
    });
  }

  void _updateSorting(MovieSortField sortField, SortDirection direction) {
    setState(() {
      _sortField = sortField;
      _sortDirection = direction;
    });
    _loadMovies();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );

    if (!mounted) return;

    final query = _searchController.text.trim();
    if (query.length >= 2) {
      _searchMovies(query);
    }
    _loadDiscoverMovies();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();

    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _searchMovies(query);
    });
  }

  Future<void> _searchMovies(String query) async {
    final settings = AppSettingsScope.of(context);
    final omdbApiKey = settings.omdbApiKey.trim();

    if (omdbApiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    List<MovieSearchResult> results = const [];
    try {
      results = await MovieMetadataService.searchMovies(
        query,
        omdbApiKey: omdbApiKey,
      );
    } catch (_) {
      results = const [];
    }

    if (!mounted) return;
    if (_searchController.text.trim() != query) return;

    setState(() {
      _isSearching = false;
      _searchResults = results;
    });
  }

  Future<void> _addFromSearchResult(MovieSearchResult result) async {
    if (_addingImdbId != null) return;
    if (_isResultAlreadyAdded(result)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.text(context, 'catalog_duplicate_blocked')),
        ),
      );
      return;
    }

    final settings = AppSettingsScope.of(context);
    final omdbApiKey = settings.omdbApiKey.trim();
    final tmdbApiKey = settings.tmdbApiKey.trim();

    setState(() {
      _addingImdbId = result.imdbId;
    });

    MovieMetadata? metadata;
    if (omdbApiKey.isNotEmpty) {
      metadata = await MovieMetadataService.fetchMovieMetadataByImdbId(
        result.imdbId,
        omdbApiKey: omdbApiKey,
        tmdbApiKey: tmdbApiKey,
      );
    }

    if (!mounted) return;

    final addResult = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMoviePage(
          initialTitle: result.title,
          initialYear: result.year,
          initialPosterUrl: metadata?.posterUrl ?? result.posterUrl,
          initialMetadata: metadata,
          initialImdbId: result.imdbId,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _addingImdbId = null;
    });

    if (addResult == true) {
      _loadMovies();
      _tabController.animateTo(0);
    }
  }

  Future<void> _showSearchResultDetails(MovieSearchResult result) async {
    String t(String key) => AppStrings.text(context, key);
    final settings = AppSettingsScope.of(context);
    final omdbApiKey = settings.omdbApiKey.trim();
    final tmdbApiKey = settings.tmdbApiKey.trim();
    final alreadyAdded = _isResultAlreadyAdded(result);

    final metadataFuture = omdbApiKey.isEmpty
        ? Future.value(null)
        : MovieMetadataService.fetchMovieMetadataByImdbId(
            result.imdbId,
            omdbApiKey: omdbApiKey,
            tmdbApiKey: tmdbApiKey,
          );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: FutureBuilder<MovieMetadata?>(
            future: metadataFuture,
            builder: (context, snapshot) {
              final metadata = snapshot.data;
              final posterUrl = metadata?.posterUrl ?? result.posterUrl;
              final year = metadata?.year ?? result.year;
              final genre = metadata?.genre ?? '';
              final director = metadata?.director ?? '';
              final runtime = metadata?.runtime ?? '';
              final plot = metadata?.plot ?? '';
              final imdb = metadata?.imdbRating;
              final rotten = metadata?.rottenTomatoesRating ?? '';

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (posterUrl != null && posterUrl.isNotEmpty)
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                            posterUrl,
                            width: 190,
                            height: 270,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _emptyDiscoverPoster(),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: SizedBox(
                          width: 190,
                          height: 270,
                          child: _emptyDiscoverPoster(),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      result.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            year.isEmpty ? t('catalog_year_unknown') : year,
                          ),
                        ),
                        if (imdb != null)
                          Chip(label: Text('IMDb ${imdb.toStringAsFixed(1)}')),
                        if (rotten.isNotEmpty) Chip(label: Text('RT $rotten')),
                      ],
                    ),
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(t('catalog_loading_details')),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      if (genre.isNotEmpty) Text('${t('genre')}: $genre'),
                      if (director.isNotEmpty)
                        Text('${t('director')}: $director'),
                      if (runtime.isNotEmpty) Text('${t('runtime')}: $runtime'),
                      if (plot.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(plot),
                      ],
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: alreadyAdded
                          ? FilledButton.tonal(
                              onPressed: null,
                              child: Text(t('catalog_already_added')),
                            )
                          : FilledButton.icon(
                              onPressed: _addingImdbId == result.imdbId
                                  ? null
                                  : () async {
                                      Navigator.pop(sheetContext);
                                      await _addFromSearchResult(result);
                                    },
                              icon: _addingImdbId == result.imdbId
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.playlist_add),
                              label: Text(t('catalog_add_from_details')),
                            ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text(t('close')),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showDiscoverMovieDetails(DiscoverMovie movie) async {
    String t(String key) => AppStrings.text(context, key);
    final settings = AppSettingsScope.of(context);
    final tmdbApiKey = settings.tmdbApiKey.trim();
    if (tmdbApiKey.isEmpty) return;

    final detailsFuture = MovieMetadataService.fetchTmdbMovieDetails(
      movie.tmdbId,
      tmdbApiKey: tmdbApiKey,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: FutureBuilder<TmdbMovieDetails?>(
            future: detailsFuture,
            builder: (context, snapshot) {
              final details = snapshot.data;
              final data =
                  details ??
                  TmdbMovieDetails(
                    tmdbId: movie.tmdbId,
                    title: movie.title,
                    year: movie.year,
                    posterUrl: movie.posterUrl,
                    overview: movie.overview,
                  );

              final alreadyAdded = _isTmdbSuggestionAlreadyAdded(data);
              final buttonKey = data.imdbId.isEmpty
                  ? 'tmdb-${data.tmdbId}'
                  : data.imdbId;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((data.posterUrl ?? '').isNotEmpty)
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                            data.posterUrl!,
                            width: 190,
                            height: 270,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _emptyDiscoverPoster(),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: SizedBox(
                          width: 190,
                          height: 270,
                          child: _emptyDiscoverPoster(),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      data.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            data.year.isEmpty
                                ? t('catalog_year_unknown')
                                : data.year,
                          ),
                        ),
                        if (movie.voteAverage > 0)
                          Chip(
                            label: Text(
                              'TMDB ${movie.voteAverage.toStringAsFixed(1)}',
                            ),
                          ),
                      ],
                    ),
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(t('catalog_loading_details')),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      if (data.genre.isNotEmpty)
                        Text('${t('genre')}: ${data.genre}'),
                      if (data.director.isNotEmpty)
                        Text('${t('director')}: ${data.director}'),
                      if (data.runtime.isNotEmpty)
                        Text('${t('runtime')}: ${data.runtime}'),
                      if (data.overview.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(data.overview),
                      ],
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: alreadyAdded
                          ? FilledButton.tonal(
                              onPressed: null,
                              child: Text(t('catalog_already_added')),
                            )
                          : FilledButton.icon(
                              onPressed: _addingImdbId == buttonKey
                                  ? null
                                  : () async {
                                      Navigator.pop(sheetContext);
                                      await _addFromTmdbDetails(data);
                                    },
                              icon: _addingImdbId == buttonKey
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.playlist_add),
                              label: Text(t('catalog_add_from_details')),
                            ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text(t('close')),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _addFromTmdbDetails(TmdbMovieDetails details) async {
    final settings = AppSettingsScope.of(context);
    final omdbApiKey = settings.omdbApiKey.trim();
    final tmdbApiKey = settings.tmdbApiKey.trim();
    final buttonKey = details.imdbId.isEmpty
        ? 'tmdb-${details.tmdbId}'
        : details.imdbId;

    if (_addingImdbId != null) return;

    final isDuplicate = _isTmdbSuggestionAlreadyAdded(details);
    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.text(context, 'catalog_duplicate_blocked')),
        ),
      );
      return;
    }

    setState(() {
      _addingImdbId = buttonKey;
    });

    MovieMetadata? omdbMetadata;
    if (details.imdbId.isNotEmpty && omdbApiKey.isNotEmpty) {
      omdbMetadata = await MovieMetadataService.fetchMovieMetadataByImdbId(
        details.imdbId,
        omdbApiKey: omdbApiKey,
        tmdbApiKey: tmdbApiKey,
      );
    }

    if (!mounted) return;

    final seedMetadata =
        omdbMetadata ??
        MovieMetadata(
          imdbId: details.imdbId,
          posterUrl: details.posterUrl,
          year: details.year,
          genre: details.genre,
          director: details.director,
          runtime: details.runtime,
          plot: details.overview,
        );

    final addResult = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMoviePage(
          initialTitle: details.title,
          initialYear: details.year,
          initialPosterUrl: details.posterUrl,
          initialMetadata: seedMetadata,
          initialImdbId: details.imdbId,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _addingImdbId = null;
    });

    if (addResult == true) {
      _loadMovies();
      _tabController.animateTo(0);
    }
  }

  Widget _emptyDiscoverPoster() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 36,
        ),
      ),
    );
  }

  void _openDrawer(BuildContext context) {
    Scaffold.of(context).openDrawer();
  }

  void _goToTab(int index) {
    Navigator.pop(context);
    _tabController.animateTo(index);
  }

  void _setGenreFilter(String? genre) {
    setState(() {
      _selectedGenre = genre;
    });
    Navigator.pop(context);
    _tabController.animateTo(0);
  }

  void _setCategoryFilter(String? category) {
    setState(() {
      _selectedCategory = category;
    });
    Navigator.pop(context);
    _tabController.animateTo(0);
  }

  Future<void> _showMovieDetails(Movie movie) async {
    String t(String key) => AppStrings.text(context, key);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movie.year.isNotEmpty
                      ? '${movie.title} (${movie.year})'
                      : movie.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        '${t('personal_rating')}: ${movie.rating.toStringAsFixed(1)}',
                      ),
                    ),
                    if (movie.imdbRating != null)
                      Chip(
                        label: Text(
                          'IMDb ${movie.imdbRating!.toStringAsFixed(1)}',
                        ),
                      ),
                    if (movie.rottenTomatoesRating.isNotEmpty)
                      Chip(label: Text('RT ${movie.rottenTomatoesRating}')),
                  ],
                ),
                const SizedBox(height: 12),
                if (movie.genre.isNotEmpty)
                  Text('${t('genre')}: ${movie.genre}'),
                if (movie.director.isNotEmpty)
                  Text('${t('director')}: ${movie.director}'),
                if (movie.runtime.isNotEmpty)
                  Text('${t('runtime')}: ${movie.runtime}'),
                if (movie.category.isNotEmpty)
                  Text('${t('category')}: ${movie.category}'),
                if (movie.watchedAt.isNotEmpty)
                  Text('${t('watched_on')}: ${movie.watchedAt}'),
                if (movie.watchPlatform.isNotEmpty)
                  Text('${t('watch_platform')}: ${movie.watchPlatform}'),
                const SizedBox(height: 10),
                Text(
                  movie.comment.isEmpty ? t('no_comment') : movie.comment,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(context);
                        _editMovie(movie);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(t('edit')),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteMovie(movie.id!);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: Text(t('delete')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPoster(Movie movie) {
    if (movie.imagePath.isNotEmpty && File(movie.imagePath).existsSync()) {
      return Image.file(
        File(movie.imagePath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    if (movie.posterUrl.isNotEmpty) {
      return Image.network(
        movie.posterUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => const Icon(Icons.movie_creation_outlined),
      );
    }

    return const Center(child: Icon(Icons.movie_creation_outlined, size: 34));
  }

  Widget _watchedBubbleCard(Movie movie) {
    String t(String key) => AppStrings.text(context, key);
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showMovieDetails(movie),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: _buildPoster(movie),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          movie.year.isEmpty ? '-' : movie.year,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (movie.category.isNotEmpty)
                        _metricPill(movie.category),
                      _metricPill(
                        '${t('personal_rating')}: ${movie.rating.toStringAsFixed(1)}',
                      ),
                      _metricPill(
                        'IMDb ${movie.imdbRating?.toStringAsFixed(1) ?? '-'}',
                      ),
                      _metricPill(
                        'RT ${movie.rottenTomatoesRating.isEmpty ? '-' : movie.rottenTomatoesRating}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricPill(String text) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildWatchedTab(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 900
            ? 4
            : width > 680
            ? 3
            : 2;
        final movies = _filteredMovies(context);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _watchedSearchController,
                decoration: InputDecoration(
                  hintText: t('watched_search_hint'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _watchedSearchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => _watchedSearchController.clear(),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${t('seen_panel_title')} (${movies.length})',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (movies.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: _addMovie,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(t('manual_add_movie')),
                      ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_selectedGenre != null && _selectedGenre!.isNotEmpty)
                    InputChip(
                      label: Text('${t('drawer_genres')}: $_selectedGenre'),
                      onDeleted: () {
                        setState(() {
                          _selectedGenre = null;
                        });
                      },
                    ),
                  if (_selectedCategory != null &&
                      _selectedCategory!.isNotEmpty)
                    InputChip(
                      label: Text(
                        '${t('drawer_categories')}: $_selectedCategory',
                      ),
                      onDeleted: () {
                        setState(() {
                          _selectedCategory = null;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: movies.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.movie_filter_outlined,
                              size: 38,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              t('no_movies_yet'),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: _addMovie,
                              child: Text(t('manual_add_movie')),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        itemCount: movies.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: width > 680 ? 0.72 : 0.68,
                        ),
                        itemBuilder: (context, index) {
                          final movie = movies[index];
                          return _watchedBubbleCard(movie);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiscoverTab(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final settings = AppSettingsScope.of(context);
    final hasOmdbKey = settings.omdbApiKey.trim().isNotEmpty;
    final query = _searchController.text.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('catalog_panel_title'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  t('catalog_panel_desc'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  t('catalog_preview_hint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: t('catalog_search_hint'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.length >= 2) {
                _searchMovies(trimmed);
              }
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Builder(
              builder: (context) {
                if (!hasOmdbKey) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t('catalog_missing_key'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: _openSettings,
                          child: Text(t('catalog_open_settings')),
                        ),
                      ],
                    ),
                  );
                }

                if (query.isEmpty) {
                  return Center(
                    child: Text(
                      t('catalog_prompt'),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (_isSearching) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                        const SizedBox(height: 10),
                        Text(t('catalog_searching')),
                      ],
                    ),
                  );
                }

                if (_searchResults.isEmpty) {
                  return Center(
                    child: Text(
                      t('catalog_no_results'),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    final isAdding = _addingImdbId == result.imdbId;

                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: ListTile(
                        onTap: () => _showSearchResultDetails(result),
                        contentPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        leading: _SearchPoster(
                          posterUrl: result.posterUrl,
                          width: 58,
                          height: 84,
                        ),
                        title: Text(
                          result.year.isEmpty
                              ? result.title
                              : '${result.title} (${result.year})',
                        ),
                        subtitle: Text(
                          _isResultAlreadyAdded(result)
                              ? t('catalog_already_added')
                              : t('catalog_open_details'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: FilledButton.tonalIcon(
                          onPressed: isAdding
                              ? null
                              : () => _showSearchResultDetails(result),
                          icon: const Icon(Icons.chevron_right),
                          label: isAdding
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(t('catalog_open_details')),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverFeedTab(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final settings = AppSettingsScope.of(context);
    final hasTmdbKey = settings.tmdbApiKey.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('discover_feed_title'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  t('discover_feed_desc'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (!hasTmdbKey) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t('discover_feed_missing_key'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: _openSettings,
                          child: Text(t('catalog_open_settings')),
                        ),
                      ],
                    ),
                  );
                }

                if (_isLoadingDiscover) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                        const SizedBox(height: 10),
                        Text(t('discover_feed_loading')),
                      ],
                    ),
                  );
                }

                if (_discoverMovies.isEmpty) {
                  return Center(
                    child: Text(
                      t('discover_feed_empty'),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadDiscoverMovies,
                  child: ListView.separated(
                    itemCount: _discoverMovies.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final movie = _discoverMovies[index];

                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: ListTile(
                          onTap: () => _showDiscoverMovieDetails(movie),
                          contentPadding: const EdgeInsets.fromLTRB(
                            10,
                            8,
                            10,
                            8,
                          ),
                          leading: _SearchPoster(
                            posterUrl: movie.posterUrl,
                            width: 58,
                            height: 84,
                          ),
                          title: Text(
                            movie.year.isEmpty
                                ? movie.title
                                : '${movie.title} (${movie.year})',
                          ),
                          subtitle: Text(t('catalog_open_details')),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E242F)
                    : const Color(0xFFF7D365),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.32)
                          : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.movie_filter_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('app_brand'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t('drawer_subtitle'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 12, endIndent: 12),
            ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: Text(t('tab_watched')),
              onTap: () => _goToTab(0),
            ),
            ListTile(
              leading: const Icon(Icons.travel_explore_outlined),
              title: Text(t('tab_discover')),
              onTap: () => _goToTab(1),
            ),
            ListTile(
              leading: const Icon(Icons.explore_outlined),
              title: Text(t('tab_discover_feed')),
              onTap: () => _goToTab(2),
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: Text(t('manual_add_movie')),
              onTap: () {
                Navigator.pop(context);
                _addMovie();
              },
            ),
            ExpansionTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(t('drawer_genres')),
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                ListTile(
                  title: Text(t('drawer_all_genres')),
                  selected: _selectedGenre == null,
                  onTap: () => _setGenreFilter(null),
                ),
                ..._availableGenres.map(
                  (genre) => ListTile(
                    title: Text(genre),
                    selected: _selectedGenre == genre,
                    onTap: () => _setGenreFilter(genre),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              leading: const Icon(Icons.label_outline_rounded),
              title: Text(t('drawer_categories')),
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                ListTile(
                  title: Text(t('drawer_all_categories')),
                  selected: _selectedCategory == null,
                  onTap: () => _setCategoryFilter(null),
                ),
                ..._availableCategories(context).map(
                  (category) => ListTile(
                    title: Text(category),
                    selected: _selectedCategory == category,
                    onTap: () => _setCategoryFilter(category),
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Divider(height: 1, indent: 12, endIndent: 12),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(t('settings')),
              onTap: () {
                Navigator.pop(context);
                _openSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topBg = isDark ? const Color(0xFF111720) : const Color(0xFFFFF4CF);
    final bottomBg = isDark ? const Color(0xFF0D1219) : const Color(0xFFF7F1E1);

    return Scaffold(
      drawer: _buildDrawer(context),
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              onPressed: () => _openDrawer(context),
              icon: const Icon(Icons.menu_rounded),
            );
          },
        ),
        title: Text(
          t('app_brand'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: t('select_sort'),
            onSelected: (value) {
              switch (value) {
                case 'rating_desc':
                  _updateSorting(MovieSortField.rating, SortDirection.desc);
                  break;
                case 'rating_asc':
                  _updateSorting(MovieSortField.rating, SortDirection.asc);
                  break;
                case 'title_asc':
                  _updateSorting(MovieSortField.title, SortDirection.asc);
                  break;
                case 'category_asc':
                  _updateSorting(MovieSortField.category, SortDirection.asc);
                  break;
                case 'watched_desc':
                  _updateSorting(MovieSortField.watchedAt, SortDirection.desc);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rating_desc',
                child: Text(t('rating_desc')),
              ),
              PopupMenuItem(value: 'rating_asc', child: Text(t('rating_asc'))),
              PopupMenuItem(value: 'title_asc', child: Text(t('title_asc'))),
              PopupMenuItem(
                value: 'category_asc',
                child: Text(t('category_asc')),
              ),
              PopupMenuItem(
                value: 'watched_desc',
                child: Text(t('last_watched')),
              ),
            ],
            icon: const Icon(Icons.sort),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Theme.of(context).colorScheme.onPrimary,
                unselectedLabelColor: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant,
                tabs: [
                  Tab(text: t('tab_watched')),
                  Tab(text: t('tab_discover')),
                  Tab(text: t('tab_discover_feed')),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topBg, bottomBg],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -70,
              top: -40,
              child: _backgroundBubble(
                size: 180,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.07),
              ),
            ),
            Positioned(
              right: -60,
              top: 160,
              child: _backgroundBubble(
                size: 150,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.05),
              ),
            ),
            Positioned(
              right: -40,
              bottom: -40,
              child: _backgroundBubble(
                size: 140,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.06),
              ),
            ),
            TabBarView(
              controller: _tabController,
              children: [
                _buildWatchedTab(context),
                _buildDiscoverTab(context),
                _buildDiscoverFeedTab(context),
              ],
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _currentTab == 0
          ? FloatingActionButton.extended(
              onPressed: _addMovie,
              icon: const Icon(Icons.add),
              label: Text(t('manual_add_movie')),
            )
          : null,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final active = _currentTab == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _backgroundBubble({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SearchPoster extends StatelessWidget {
  final String? posterUrl;
  final double width;
  final double height;

  const _SearchPoster({this.posterUrl, this.width = 44, this.height = 62});

  @override
  Widget build(BuildContext context) {
    final url = posterUrl ?? '';

    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(context),
        ),
      );
    }

    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.movie_creation_outlined,
        size: width * 0.48,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
