import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:share_plus/share_plus.dart';

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

enum DiscoverSortField {
  popularityDesc,
  popularityAsc,
  ratingDesc,
  ratingAsc,
  titleAsc,
  titleDesc,
}

enum WatchlistSortField { addedDesc, titleAsc, ratingDesc }

class _MovieListPageState extends State<MovieListPage>
    with SingleTickerProviderStateMixin {
  static const _watchlistTag = '__watchlist__';
  static const Map<int, String> _tmdbGenreNames = {
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Sci-Fi',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
  };

  final _searchController = TextEditingController();
  final _watchedSearchController = TextEditingController();
  final _discoverSearchFocusNode = FocusNode();
  final _homeCarouselController = PageController(viewportFraction: 0.86);

  late final TabController _tabController;

  List<Movie> _movies = [];
  List<MovieSearchResult> _searchResults = [];
  List<DiscoverMovie> _discoverMovies = [];
  MovieSortField _sortField = MovieSortField.rating;
  SortDirection _sortDirection = SortDirection.desc;
  int _currentTab = 0;

  int? _selectedDiscoverGenreId;
  bool _watchedListView = false;
  DiscoverSortField _discoverSortField = DiscoverSortField.popularityDesc;
  WatchlistSortField _watchlistSortField = WatchlistSortField.addedDesc;
  int _homeCarouselIndex = 0;
  String _watchedSearchQuery = '';
  String _lastTmdbApiKey = '';
  String _lastLanguageCode = '';
  bool _isRefreshingLibraryLocalization = false;
  bool _isSearching = false;
  bool _isLoadingDiscover = false;
  bool _hasLoadedDiscoverOnce = false;
  String? _discoverLoadError;
  String? _addingImdbId;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    _homeCarouselController.addListener(_onHomeCarouselChanged);
    _loadMovies();
    _searchController.addListener(_onSearchChanged);
    _watchedSearchController.addListener(_onWatchedSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = AppSettingsScope.of(context);
    final tmdbApiKey = settings.tmdbApiKey.trim();
    final languageCode = settings.languageCode;

    final languageChanged =
        _lastLanguageCode.isNotEmpty && _lastLanguageCode != languageCode;
    final tmdbChanged = tmdbApiKey != _lastTmdbApiKey;

    if (tmdbChanged || languageChanged) {
      _loadDiscoverMovies();
    }

    if (languageChanged) {
      _reloadSearchForCurrentLanguage();
      unawaited(_refreshLibraryLocalization(languageCode: languageCode));
    }

    _lastTmdbApiKey = tmdbApiKey;
    _lastLanguageCode = languageCode;
  }

  void _reloadSearchForCurrentLanguage() {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      if (_searchResults.isNotEmpty || _isSearching) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
      return;
    }

    setState(() {
      _isSearching = true;
    });
    _searchMovies(query);
  }

  Future<void> _refreshLibraryLocalization({
    required String languageCode,
  }) async {
    if (_isRefreshingLibraryLocalization) return;

    final settings = AppSettingsScope.of(context);
    final tmdbApiKey = settings.tmdbApiKey.trim();
    if (tmdbApiKey.isEmpty || _movies.isEmpty) return;

    _isRefreshingLibraryLocalization = true;
    try {
      final candidates = _movies
          .where((movie) => movie.imdbId.trim().isNotEmpty)
          .toList(growable: false);
      if (candidates.isEmpty) return;

      var hasChanges = false;
      for (final movie in candidates) {
        final localized =
            await MovieMetadataService.fetchLocalizedMetadataByImdbId(
              movie.imdbId,
              tmdbApiKey: tmdbApiKey,
              languageCode: languageCode,
            );
        if (localized == null) continue;

        final nextTitle = (localized.title ?? movie.title).trim();
        final nextYear = (localized.year ?? movie.year).trim();
        final nextGenre = (localized.genre ?? movie.genre).trim();
        final nextDirector = (localized.director ?? movie.director).trim();
        final nextRuntime = (localized.runtime ?? movie.runtime).trim();
        final nextPosterUrl = (localized.posterUrl ?? movie.posterUrl).trim();

        final changed =
            nextTitle != movie.title ||
            nextYear != movie.year ||
            nextGenre != movie.genre ||
            nextDirector != movie.director ||
            nextRuntime != movie.runtime ||
            nextPosterUrl != movie.posterUrl;
        if (!changed) continue;

        final updatedMovie = Movie(
          id: movie.id,
          title: nextTitle.isEmpty ? movie.title : nextTitle,
          rating: movie.rating,
          comment: movie.comment,
          imagePath: movie.imagePath,
          posterUrl: nextPosterUrl,
          year: nextYear,
          genre: nextGenre,
          director: nextDirector,
          runtime: nextRuntime,
          watchedAt: movie.watchedAt,
          watchPlatform: movie.watchPlatform,
          imdbRating: movie.imdbRating,
          rottenTomatoesRating: movie.rottenTomatoesRating,
          imdbId: movie.imdbId,
          category: movie.category,
        );
        await DatabaseHelper.saveMovie(updatedMovie);
        hasChanges = true;
      }

      if (hasChanges && mounted) {
        await _loadMovies();
      }
    } finally {
      _isRefreshingLibraryLocalization = false;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _discoverSearchFocusNode.dispose();
    _watchedSearchController.removeListener(_onWatchedSearchChanged);
    _watchedSearchController.dispose();
    _homeCarouselController.removeListener(_onHomeCarouselChanged);
    _homeCarouselController.dispose();
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
    _loadMovies();
    if (_currentTab == 0) {
      _loadDiscoverMovies();
    }
  }

  void _onHomeCarouselChanged() {
    final page = _homeCarouselController.page?.round() ?? 0;
    if (!mounted || page == _homeCarouselIndex) return;
    setState(() {
      _homeCarouselIndex = page;
    });
  }

  void _onWatchedSearchChanged() {
    final next = _watchedSearchController.text.trim();
    if (_watchedSearchQuery == next) return;
    setState(() {
      _watchedSearchQuery = next;
    });
  }

  bool _isWatchlistMovie(Movie movie) {
    return movie.category.trim().toLowerCase() == _watchlistTag;
  }

  List<Movie> _watchedMovies() {
    return _movies.where((movie) => !_isWatchlistMovie(movie)).toList();
  }

  List<Movie> _watchlistMovies() {
    return _movies.where((movie) => _isWatchlistMovie(movie)).toList();
  }

  List<Movie> _sortedWatchlistMovies() {
    final watchlist = _watchlistMovies();
    switch (_watchlistSortField) {
      case WatchlistSortField.addedDesc:
        watchlist.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
        break;
      case WatchlistSortField.titleAsc:
        watchlist.sort((a, b) => a.title.compareTo(b.title));
        break;
      case WatchlistSortField.ratingDesc:
        watchlist.sort((a, b) => b.rating.compareTo(a.rating));
        break;
    }
    return watchlist;
  }

  List<Movie> _filteredMovies(BuildContext context) {
    final query = _watchedSearchQuery.toLowerCase();

    return _watchedMovies().where((movie) {
      final title = movie.title.toLowerCase();
      if (query.isNotEmpty && !title.contains(query)) {
        return false;
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

  Future<void> _loadDiscoverMovies() async {
    final settings = AppSettingsScope.of(context);
    final tmdbApiKey = settings.tmdbApiKey.trim();
    final languageCode = settings.languageCode;

    if (tmdbApiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _discoverMovies = [];
        _isLoadingDiscover = false;
        _hasLoadedDiscoverOnce = true;
        _discoverLoadError = null;
      });
      return;
    }

    setState(() {
      _isLoadingDiscover = true;
      _discoverLoadError = null;
    });

    List<DiscoverMovie> movies = const [];
    String? discoverLoadErrorKey;
    try {
      movies = await MovieMetadataService.discoverMovies(
        tmdbApiKey: tmdbApiKey,
        languageCode: languageCode,
      );
    } on SocketException {
      movies = const [];
      discoverLoadErrorKey = 'discover_feed_offline';
    } on TimeoutException {
      movies = const [];
      discoverLoadErrorKey = 'discover_feed_offline';
    } catch (_) {
      movies = const [];
      discoverLoadErrorKey = 'discover_feed_error';
    }

    if (!mounted) return;
    setState(() {
      _isLoadingDiscover = false;
      _hasLoadedDiscoverOnce = true;
      _discoverMovies = movies;
      _discoverLoadError = discoverLoadErrorKey;
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

  Future<T?> _showSortModal<T>({
    required String title,
    required T currentValue,
    required List<_SortOption<T>> options,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  ...options.map(
                    (option) => ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: () => Navigator.pop(sheetContext, option.value),
                      title: Text(option.label),
                      trailing: option.value == currentValue
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(sheetContext).colorScheme.primary,
                            )
                          : const Icon(Icons.radio_button_unchecked),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openWatchedSortModal() async {
    String t(String key) => AppStrings.text(context, key);
    final currentKey = switch ((_sortField, _sortDirection)) {
      (MovieSortField.rating, SortDirection.desc) => 'rating_desc',
      (MovieSortField.rating, SortDirection.asc) => 'rating_asc',
      (MovieSortField.title, SortDirection.asc) => 'title_asc',
      (MovieSortField.watchedAt, SortDirection.desc) => 'watched_desc',
      _ => 'rating_desc',
    };
    final selected = await _showSortModal<String>(
      title: t('select_sort'),
      currentValue: currentKey,
      options: [
        _SortOption('rating_desc', t('rating_desc')),
        _SortOption('rating_asc', t('rating_asc')),
        _SortOption('title_asc', t('title_asc')),
        _SortOption('watched_desc', t('last_watched')),
      ],
    );
    if (selected == null) return;
    switch (selected) {
      case 'rating_desc':
        _updateSorting(MovieSortField.rating, SortDirection.desc);
        break;
      case 'rating_asc':
        _updateSorting(MovieSortField.rating, SortDirection.asc);
        break;
      case 'title_asc':
        _updateSorting(MovieSortField.title, SortDirection.asc);
        break;
      case 'watched_desc':
        _updateSorting(MovieSortField.watchedAt, SortDirection.desc);
        break;
    }
  }

  Future<void> _openDiscoverSortModal() async {
    String t(String key) => AppStrings.text(context, key);
    final selected = await _showSortModal<DiscoverSortField>(
      title: t('select_sort'),
      currentValue: _discoverSortField,
      options: [
        _SortOption(
          DiscoverSortField.popularityDesc,
          t('sort_popularity_desc'),
        ),
        _SortOption(DiscoverSortField.popularityAsc, t('sort_popularity_asc')),
        _SortOption(DiscoverSortField.ratingDesc, t('rating_desc')),
        _SortOption(DiscoverSortField.ratingAsc, t('rating_asc')),
        _SortOption(DiscoverSortField.titleAsc, t('title_asc')),
        _SortOption(DiscoverSortField.titleDesc, t('sort_title_desc')),
      ],
    );
    if (selected == null) return;
    setState(() {
      _discoverSortField = selected;
    });
  }

  Future<void> _openWatchlistSortModal() async {
    String t(String key) => AppStrings.text(context, key);
    final selected = await _showSortModal<WatchlistSortField>(
      title: t('select_sort'),
      currentValue: _watchlistSortField,
      options: [
        _SortOption(WatchlistSortField.addedDesc, t('watchlist_sort_added')),
        _SortOption(WatchlistSortField.titleAsc, t('watchlist_sort_title')),
        _SortOption(WatchlistSortField.ratingDesc, t('watchlist_sort_rating')),
      ],
    );
    if (selected == null) return;
    setState(() {
      _watchlistSortField = selected;
    });
  }

  void _openSettings() {
    _tabController.animateTo(4);
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
    final tmdbApiKey = settings.tmdbApiKey.trim();
    final languageCode = settings.languageCode;

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
        tmdbApiKey: tmdbApiKey,
        languageCode: languageCode,
      );
    } catch (_) {
      results = const [];
    }

    if (!mounted) return;
    final currentSettings = AppSettingsScope.of(context);
    if (_searchController.text.trim() != query ||
        currentSettings.languageCode != languageCode) {
      return;
    }

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
    final languageCode = settings.languageCode;

    setState(() {
      _addingImdbId = result.imdbId;
    });

    MovieMetadata? metadata;
    if (omdbApiKey.isNotEmpty) {
      metadata = await MovieMetadataService.fetchMovieMetadataByImdbId(
        result.imdbId,
        omdbApiKey: omdbApiKey,
        tmdbApiKey: tmdbApiKey,
        languageCode: languageCode,
      );
    }

    if (!mounted) return;

    final quickData = _CatalogPreviewData(
      title: metadata?.title ?? result.title,
      year: metadata?.year ?? result.year,
      posterUrl: metadata?.posterUrl ?? result.posterUrl,
      genre: metadata?.genre ?? '',
      director: metadata?.director ?? '',
      runtime: metadata?.runtime ?? '',
      plot: metadata?.plot ?? '',
      imdbRating: metadata?.imdbRating,
      rottenTomatoesRating: metadata?.rottenTomatoesRating ?? '',
      imdbId: result.imdbId,
    );
    final rating = await _openQuickRatingEditor(
      data: quickData,
      initialRating: 3.0,
      actionLabel: AppStrings.text(context, 'catalog_add_from_details'),
    );

    if (!mounted) return;

    setState(() {
      _addingImdbId = null;
    });

    if (rating == null) return;
    await _saveMovieFromPreview(
      data: quickData,
      rating: rating,
      imdbId: result.imdbId,
    );
  }

  Future<void> _showSearchResultDetails(MovieSearchResult result) async {
    final settings = AppSettingsScope.of(context);
    final omdbApiKey = settings.omdbApiKey.trim();
    final tmdbApiKey = settings.tmdbApiKey.trim();
    final languageCode = settings.languageCode;
    final alreadyAdded = _isResultAlreadyAdded(result);

    final initialData = _CatalogPreviewData(
      title: result.title,
      year: result.year,
      posterUrl: result.posterUrl,
      imdbId: result.imdbId,
    );

    final detailsFuture = omdbApiKey.isEmpty
        ? Future.value(initialData)
        : MovieMetadataService.fetchMovieMetadataByImdbId(
                result.imdbId,
                omdbApiKey: omdbApiKey,
                tmdbApiKey: tmdbApiKey,
                languageCode: languageCode,
              )
              .then((metadata) {
                return initialData.copyWith(
                  year: metadata?.year ?? initialData.year,
                  posterUrl: metadata?.posterUrl ?? initialData.posterUrl,
                  genre: metadata?.genre ?? '',
                  director: metadata?.director ?? '',
                  runtime: metadata?.runtime ?? '',
                  plot: metadata?.plot ?? '',
                  imdbRating: metadata?.imdbRating,
                  rottenTomatoesRating: metadata?.rottenTomatoesRating ?? '',
                  imdbId: metadata?.imdbId ?? initialData.imdbId,
                );
              })
              .catchError((_) => initialData);

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _CatalogMoviePreviewPage(
          initialData: initialData,
          detailsFuture: detailsFuture,
          primaryActionLabel: alreadyAdded
              ? AppStrings.text(context, 'catalog_already_added')
              : AppStrings.text(context, 'catalog_add_from_details'),
          primaryActionEnabled: !alreadyAdded,
          onPrimaryAction: alreadyAdded
              ? null
              : (_) async {
                  await _addFromSearchResult(result);
                },
          onFavoriteTap: alreadyAdded ? null : _addToWatchlistFromPreview,
        ),
      ),
    );
  }

  Future<void> _showDiscoverMovieDetails(DiscoverMovie movie) async {
    final settings = AppSettingsScope.of(context);
    final tmdbApiKey = settings.tmdbApiKey.trim();
    final languageCode = settings.languageCode;
    if (tmdbApiKey.isEmpty) return;

    final initialDetails = TmdbMovieDetails(
      tmdbId: movie.tmdbId,
      title: movie.title,
      year: movie.year,
      posterUrl: movie.posterUrl,
      overview: movie.overview,
    );
    final initialData = _CatalogPreviewData(
      title: movie.title,
      year: movie.year,
      posterUrl: movie.posterUrl,
      plot: movie.overview,
      tmdbRating: movie.voteAverage > 0 ? movie.voteAverage : null,
      imdbId: initialDetails.imdbId,
    );

    TmdbMovieDetails? loadedDetails;
    final detailsFuture =
        MovieMetadataService.fetchTmdbMovieDetails(
              movie.tmdbId,
              tmdbApiKey: tmdbApiKey,
              languageCode: languageCode,
            )
            .then((details) {
              loadedDetails = details;
              final data = details ?? initialDetails;
              return initialData.copyWith(
                title: data.title,
                year: data.year,
                posterUrl: data.posterUrl,
                plot: data.overview,
                genre: data.genre,
                director: data.director,
                runtime: data.runtime,
                imdbId: data.imdbId,
              );
            })
            .catchError((_) => initialData);

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _CatalogMoviePreviewPage(
          initialData: initialData,
          detailsFuture: detailsFuture,
          primaryActionLabel: _isTmdbSuggestionAlreadyAdded(initialDetails)
              ? AppStrings.text(context, 'catalog_already_added')
              : AppStrings.text(context, 'catalog_add_from_details'),
          primaryActionEnabled: !_isTmdbSuggestionAlreadyAdded(initialDetails),
          onPrimaryAction: _isTmdbSuggestionAlreadyAdded(initialDetails)
              ? null
              : (_) async {
                  await _addFromTmdbDetails(loadedDetails ?? initialDetails);
                },
          onFavoriteTap: _isTmdbSuggestionAlreadyAdded(initialDetails)
              ? null
              : _addToWatchlistFromPreview,
        ),
      ),
    );
  }

  Future<void> _addFromTmdbDetails(TmdbMovieDetails details) async {
    final settings = AppSettingsScope.of(context);
    final omdbApiKey = settings.omdbApiKey.trim();
    final tmdbApiKey = settings.tmdbApiKey.trim();
    final languageCode = settings.languageCode;
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
        languageCode: languageCode,
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
    final quickData = _CatalogPreviewData(
      title: details.title,
      year: seedMetadata.year ?? details.year,
      posterUrl: seedMetadata.posterUrl ?? details.posterUrl,
      genre: seedMetadata.genre ?? details.genre,
      director: seedMetadata.director ?? details.director,
      runtime: seedMetadata.runtime ?? details.runtime,
      plot: seedMetadata.plot ?? details.overview,
      imdbRating: seedMetadata.imdbRating,
      rottenTomatoesRating: seedMetadata.rottenTomatoesRating ?? '',
      imdbId: seedMetadata.imdbId ?? details.imdbId,
    );
    final rating = await _openQuickRatingEditor(
      data: quickData,
      initialRating: 3.0,
      actionLabel: AppStrings.text(context, 'catalog_add_from_details'),
    );

    if (!mounted) return;

    setState(() {
      _addingImdbId = null;
    });

    if (rating == null) return;

    await _saveMovieFromPreview(
      data: quickData,
      rating: rating,
      imdbId: quickData.imdbId,
    );
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

  void _goToTab(int index) {
    _tabController.animateTo(index);
  }

  void _goToDiscoverAndFocusSearch() {
    _tabController.animateTo(1);
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _discoverSearchFocusNode.requestFocus();
    });
  }

  String _nowTimestamp() {
    return DateTime.now().toIso8601String();
  }

  Future<double?> _openQuickRatingEditor({
    required _CatalogPreviewData data,
    required double initialRating,
    required String actionLabel,
  }) {
    return Navigator.push<double>(
      context,
      MaterialPageRoute(
        builder: (_) => _QuickMovieRatingPage(
          data: data,
          initialRating: initialRating,
          actionLabel: actionLabel,
        ),
      ),
    );
  }

  Future<void> _saveMovieFromPreview({
    required _CatalogPreviewData data,
    required double rating,
    required String imdbId,
    String category = '',
  }) async {
    final normalizedTitle = data.title.trim();
    if (normalizedTitle.isEmpty) return;

    final isDuplicate = await DatabaseHelper.movieExists(
      imdbId: imdbId.trim().isEmpty ? null : imdbId.trim(),
      title: normalizedTitle,
      year: data.year.trim(),
    );
    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.text(context, 'catalog_duplicate_blocked')),
        ),
      );
      return;
    }

    final movie = Movie(
      title: normalizedTitle,
      rating: rating,
      comment: data.plot,
      imagePath: '',
      posterUrl: data.posterUrl ?? '',
      year: data.year,
      genre: data.genre,
      director: data.director,
      runtime: data.runtime,
      watchedAt: _nowTimestamp(),
      watchPlatform: '',
      imdbRating: data.imdbRating,
      rottenTomatoesRating: data.rottenTomatoesRating,
      imdbId: imdbId.trim(),
      category: category,
    );

    await DatabaseHelper.saveMovie(movie);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.text(context, 'movie_saved'))),
    );
    _loadMovies();
  }

  Future<void> _addToWatchlistFromPreview(_CatalogPreviewData data) async {
    final normalizedTitle = data.title.trim();
    if (normalizedTitle.isEmpty) return;

    final isDuplicate = await DatabaseHelper.movieExists(
      imdbId: data.imdbId.trim().isEmpty ? null : data.imdbId.trim(),
      title: normalizedTitle,
      year: data.year.trim(),
    );
    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.text(context, 'catalog_duplicate_blocked')),
        ),
      );
      return;
    }

    final movie = Movie(
      title: normalizedTitle,
      rating: 0,
      comment: data.plot,
      imagePath: '',
      posterUrl: data.posterUrl ?? '',
      year: data.year,
      genre: data.genre,
      director: data.director,
      runtime: data.runtime,
      watchedAt: _nowTimestamp(),
      watchPlatform: '',
      imdbRating: data.imdbRating,
      rottenTomatoesRating: data.rottenTomatoesRating,
      imdbId: data.imdbId.trim(),
      category: _watchlistTag,
    );

    await DatabaseHelper.saveMovie(movie);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.text(context, 'watchlist_added'))),
    );
    _loadMovies();
    _tabController.animateTo(3);
  }

  Future<void> _updateMovieRating(Movie movie, double newRating) async {
    final updatedMovie = Movie(
      id: movie.id,
      title: movie.title,
      rating: newRating,
      comment: movie.comment,
      imagePath: movie.imagePath,
      posterUrl: movie.posterUrl,
      year: movie.year,
      genre: movie.genre,
      director: movie.director,
      runtime: movie.runtime,
      watchedAt: _nowTimestamp(),
      watchPlatform: movie.watchPlatform,
      imdbRating: movie.imdbRating,
      rottenTomatoesRating: movie.rottenTomatoesRating,
      imdbId: movie.imdbId,
      category: movie.category,
    );
    await DatabaseHelper.saveMovie(updatedMovie);
    if (!mounted) return;
    _loadMovies();
  }

  Future<void> _markWatchlistMovieAsWatched(Movie movie, double rating) async {
    final updatedMovie = Movie(
      id: movie.id,
      title: movie.title,
      rating: rating,
      comment: movie.comment,
      imagePath: movie.imagePath,
      posterUrl: movie.posterUrl,
      year: movie.year,
      genre: movie.genre,
      director: movie.director,
      runtime: movie.runtime,
      watchedAt: _nowTimestamp(),
      watchPlatform: movie.watchPlatform,
      imdbRating: movie.imdbRating,
      rottenTomatoesRating: movie.rottenTomatoesRating,
      imdbId: movie.imdbId,
      category: '',
    );
    await DatabaseHelper.saveMovie(updatedMovie);
    if (!mounted) return;
    _loadMovies();
    _tabController.animateTo(2);
  }

  Future<_CatalogPreviewData> _resolveMoviePreviewData(Movie movie) async {
    final seedData = _CatalogPreviewData(
      title: movie.title,
      year: movie.year,
      posterUrl: movie.posterUrl.isNotEmpty ? movie.posterUrl : null,
      genre: movie.genre,
      director: movie.director,
      runtime: movie.runtime,
      plot: movie.comment,
      imdbRating: movie.imdbRating,
      rottenTomatoesRating: movie.rottenTomatoesRating,
      imdbId: movie.imdbId,
    );

    final imdbId = movie.imdbId.trim();
    if (imdbId.isEmpty) return seedData;

    final settings = AppSettingsScope.of(context);
    final omdbApiKey = settings.omdbApiKey.trim();
    final tmdbApiKey = settings.tmdbApiKey.trim();
    final languageCode = settings.languageCode;

    try {
      MovieMetadata? metadata;
      if (omdbApiKey.isNotEmpty) {
        metadata = await MovieMetadataService.fetchMovieMetadataByImdbId(
          imdbId,
          omdbApiKey: omdbApiKey,
          tmdbApiKey: tmdbApiKey,
          languageCode: languageCode,
        );
      } else if (tmdbApiKey.isNotEmpty) {
        metadata = await MovieMetadataService.fetchLocalizedMetadataByImdbId(
          imdbId,
          tmdbApiKey: tmdbApiKey,
          languageCode: languageCode,
        );
      }

      if (metadata == null) return seedData;

      return seedData.copyWith(
        title: metadata.title ?? seedData.title,
        year: metadata.year ?? seedData.year,
        posterUrl: metadata.posterUrl ?? seedData.posterUrl,
        genre: metadata.genre ?? seedData.genre,
        director: metadata.director ?? seedData.director,
        runtime: metadata.runtime ?? seedData.runtime,
        plot: metadata.plot ?? seedData.plot,
        imdbRating: metadata.imdbRating ?? seedData.imdbRating,
        rottenTomatoesRating:
            metadata.rottenTomatoesRating ?? seedData.rottenTomatoesRating,
        imdbId: metadata.imdbId ?? seedData.imdbId,
      );
    } catch (_) {
      return seedData;
    }
  }

  Future<void> _showMovieDetails(Movie movie) async {
    final changeRatingLabel = AppStrings.text(context, 'change_rating');
    final data = _CatalogPreviewData(
      title: movie.title,
      year: movie.year,
      posterUrl: movie.posterUrl.isNotEmpty ? movie.posterUrl : null,
      genre: movie.genre,
      director: movie.director,
      runtime: movie.runtime,
      plot: movie.comment,
      imdbRating: movie.imdbRating,
      rottenTomatoesRating: movie.rottenTomatoesRating,
      imdbId: movie.imdbId,
    );

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _CatalogMoviePreviewPage(
          initialData: data,
          detailsFuture: _resolveMoviePreviewData(movie),
          primaryActionLabel: changeRatingLabel,
          primaryActionEnabled: true,
          onPrimaryAction: (latestData) async {
            final newRating = await _openQuickRatingEditor(
              data: latestData,
              initialRating: movie.rating,
              actionLabel: changeRatingLabel,
            );
            if (newRating == null) return;
            await _updateMovieRating(movie, newRating);
          },
        ),
      ),
    );
  }

  Future<void> _showWatchlistMovieDetails(Movie movie) async {
    final markWatchedLabel = AppStrings.text(context, 'mark_as_watched');
    final data = _CatalogPreviewData(
      title: movie.title,
      year: movie.year,
      posterUrl: movie.posterUrl.isNotEmpty ? movie.posterUrl : null,
      genre: movie.genre,
      director: movie.director,
      runtime: movie.runtime,
      plot: movie.comment,
      imdbRating: movie.imdbRating,
      rottenTomatoesRating: movie.rottenTomatoesRating,
      imdbId: movie.imdbId,
    );

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _CatalogMoviePreviewPage(
          initialData: data,
          detailsFuture: _resolveMoviePreviewData(movie),
          primaryActionLabel: markWatchedLabel,
          primaryActionEnabled: true,
          onPrimaryAction: (latestData) async {
            final rating = await _openQuickRatingEditor(
              data: latestData,
              initialRating: 3.0,
              actionLabel: markWatchedLabel,
            );
            if (rating == null) return;
            await _markWatchlistMovieAsWatched(movie, rating);
          },
        ),
      ),
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

  String _formatRatingValue(double value) {
    final raw = value.toStringAsFixed(1);
    final languageCode = AppSettingsScope.of(context).languageCode;
    if (languageCode.toLowerCase().startsWith('de')) {
      return raw.replaceAll('.', ',');
    }
    return raw;
  }

  String _formatRatingOutOfFive(double value) {
    return '${_formatRatingValue(value)} / ${_formatRatingValue(5.0)}';
  }

  Widget _watchedBubbleCard(Movie movie) {
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
                      _metricPill(_formatRatingOutOfFive(movie.rating)),
                      _sourceRatingBadge(
                        icon: FontAwesomeIcons.imdb,
                        value: movie.imdbRating?.toStringAsFixed(1) ?? '-',
                        background: const Color(0xFFF5C74C),
                        foreground: const Color(0xFF3A2A00),
                      ),
                      _sourceRatingBadge(
                        useRottenLogo: true,
                        value: movie.rottenTomatoesRating.isEmpty
                            ? '-'
                            : movie.rottenTomatoesRating,
                        background: const Color(0x88E6463D),
                        foreground: Colors.white,
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFB322)),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _sourceRatingBadge({
    IconData? icon,
    bool useRottenLogo = false,
    required String value,
    required Color background,
    required Color foreground,
  }) {
    final resolvedIcon = icon ?? Icons.circle;
    final isFontAwesome = resolvedIcon.fontPackage == 'font_awesome_flutter';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (useRottenLogo)
            const _RottenTomatoMark(size: 12)
          else if (isFontAwesome)
            FaIcon(resolvedIcon, size: 12, color: foreground)
          else
            Icon(resolvedIcon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _watchedListTile(Movie movie) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        onTap: () => _showMovieDetails(movie),
        leading: _SearchPoster(
          posterUrl: movie.posterUrl,
          width: 58,
          height: 84,
        ),
        title: Text(
          movie.year.isEmpty ? movie.title : '${movie.title} (${movie.year})',
        ),
        subtitle: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _metricPill(_formatRatingOutOfFive(movie.rating)),
            _sourceRatingBadge(
              icon: FontAwesomeIcons.imdb,
              value: movie.imdbRating?.toStringAsFixed(1) ?? '-',
              background: const Color(0xFFF5C74C),
              foreground: const Color(0xFF3A2A00),
            ),
            _sourceRatingBadge(
              useRottenLogo: true,
              value: movie.rottenTomatoesRating.isEmpty
                  ? '-'
                  : movie.rottenTomatoesRating,
              background: const Color(0x88E6463D),
              foreground: Colors.white,
            ),
          ],
        ),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                child: Text(
                  '${t('seen_panel_title')} (${movies.length})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
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
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (movies.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: _addMovie,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(t('manual_add_movie')),
                      ),
                    if (movies.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () {
                          setState(() {
                            _watchedListView = !_watchedListView;
                          });
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB322),
                          foregroundColor: const Color(0xFF3A2800),
                        ),
                        icon: Icon(
                          _watchedListView
                              ? Icons.grid_view_rounded
                              : Icons.view_list_rounded,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
                    : _watchedListView
                    ? ListView.separated(
                        itemCount: movies.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final movie = movies[index];
                          return _watchedListTile(movie);
                        },
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

  List<MapEntry<int, String>> _discoverGenreEntries() {
    final counts = <int, int>{};
    for (final movie in _discoverMovies) {
      for (final genreId in movie.genreIds) {
        counts.update(genreId, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        final aName = _tmdbGenreNames[a.key] ?? 'Genre ${a.key}';
        final bName = _tmdbGenreNames[b.key] ?? 'Genre ${b.key}';
        return aName.compareTo(bName);
      });

    return entries
        .map((entry) {
          final name = _tmdbGenreNames[entry.key];
          if (name == null) return null;
          return MapEntry(entry.key, name);
        })
        .whereType<MapEntry<int, String>>()
        .take(10)
        .toList();
  }

  List<MapEntry<int, String>> _homeGenreEntries(
    List<MapEntry<int, String>> source,
  ) {
    final byId = <int, String>{
      for (final entry in source) entry.key: entry.value,
    };
    final ordered = <MapEntry<int, String>>[];

    for (final prioritizedId in const [28, 35]) {
      final name = byId[prioritizedId];
      if (name != null) {
        ordered.add(MapEntry(prioritizedId, name));
      }
    }

    for (final entry in source) {
      final alreadyIncluded = ordered.any((item) => item.key == entry.key);
      if (!alreadyIncluded) {
        ordered.add(entry);
      }
    }

    return ordered;
  }

  List<DiscoverMovie> _filteredDiscoverFeedMovies() {
    Iterable<DiscoverMovie> movies = _discoverMovies;
    if (_selectedDiscoverGenreId != null) {
      movies = movies.where(
        (movie) => movie.genreIds.contains(_selectedDiscoverGenreId),
      );
    }
    final sorted = movies.toList();
    switch (_discoverSortField) {
      case DiscoverSortField.popularityDesc:
        sorted.sort((a, b) => b.popularity.compareTo(a.popularity));
        break;
      case DiscoverSortField.popularityAsc:
        sorted.sort((a, b) => a.popularity.compareTo(b.popularity));
        break;
      case DiscoverSortField.ratingDesc:
        sorted.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
        break;
      case DiscoverSortField.ratingAsc:
        sorted.sort((a, b) => a.voteAverage.compareTo(b.voteAverage));
        break;
      case DiscoverSortField.titleAsc:
        sorted.sort((a, b) => a.title.compareTo(b.title));
        break;
      case DiscoverSortField.titleDesc:
        sorted.sort((a, b) => b.title.compareTo(a.title));
        break;
    }
    return sorted;
  }

  Widget _buildDiscoverTab(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final settings = AppSettingsScope.of(context);
    final hasOmdbKey = settings.omdbApiKey.trim().isNotEmpty;
    final hasTmdbKey = settings.tmdbApiKey.trim().isNotEmpty;
    final query = _searchController.text.trim();
    final discoverFeedMovies = _filteredDiscoverFeedMovies();
    final genreEntries = _discoverGenreEntries();

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
            focusNode: _discoverSearchFocusNode,
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
                if (query.isEmpty) {
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

                  if (_isLoadingDiscover && discoverFeedMovies.isEmpty) {
                    return const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    );
                  }

                  if (_discoverLoadError != null &&
                      discoverFeedMovies.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t(_discoverLoadError ?? 'discover_feed_error'),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: _loadDiscoverMovies,
                            child: Text(t('retry')),
                          ),
                        ],
                      ),
                    );
                  }

                  if (discoverFeedMovies.isEmpty) {
                    return Center(
                      child: Text(
                        t('discover_feed_empty'),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(t('drawer_all_genres')),
                                      selected:
                                          _selectedDiscoverGenreId == null,
                                      onSelected: (_) {
                                        setState(() {
                                          _selectedDiscoverGenreId = null;
                                        });
                                      },
                                    ),
                                  ),
                                  ...genreEntries.map(
                                    (entry) => Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(entry.value),
                                        selected:
                                            _selectedDiscoverGenreId ==
                                            entry.key,
                                        onSelected: (_) {
                                          setState(() {
                                            _selectedDiscoverGenreId =
                                                entry.key;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: t('select_sort'),
                            onPressed: _openDiscoverSortModal,
                            icon: const Icon(Icons.tune_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: discoverFeedMovies.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final movie = discoverFeedMovies[index];
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
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
                                subtitle: Text(
                                  '${t('sort_popularity_desc')}: ${movie.popularity.toStringAsFixed(0)}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }

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

  Widget _buildHomeTab(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final settings = AppSettingsScope.of(context);
    final hasTmdbKey = settings.tmdbApiKey.trim().isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    final heroMovies = _discoverMovies.take(5).toList();
    final heroIds = heroMovies.map((movie) => movie.tmdbId).toSet();
    final popularMovies = _discoverMovies
        .where((movie) => !heroIds.contains(movie.tmdbId))
        .take(16)
        .toList();
    final highlightedIds = {
      ...heroIds,
      ...popularMovies.map((movie) => movie.tmdbId),
    };
    final genreEntries = _discoverGenreEntries();
    final homeGenreEntries = _homeGenreEntries(genreEntries);

    final accent = const Color(0xFF1ED2E8);

    if (hasTmdbKey && !_hasLoadedDiscoverOnce) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    if (hasTmdbKey && _discoverLoadError != null && heroMovies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t(_discoverLoadError ?? 'discover_feed_error'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: _loadDiscoverMovies,
                    child: Text(t('retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _loadDiscoverMovies,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('app_brand'),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t('home_greeting_subtitle'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _homeIconButton(
                    context: context,
                    icon: Icons.person_outline_rounded,
                    onTap: _openSettings,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _goToDiscoverAndFocusSearch,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('home_search_hint'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!hasTmdbKey)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 22, 14, 18),
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
              )
            else if (_isLoadingDiscover && heroMovies.isEmpty)
              const SizedBox(
                height: 220,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              )
            else if (heroMovies.isEmpty)
              SizedBox(
                height: 220,
                child: Center(
                  child: Text(
                    t('discover_feed_empty'),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 236,
                child: PageView.builder(
                  controller: _homeCarouselController,
                  itemCount: heroMovies.length,
                  itemBuilder: (context, index) {
                    final movie = heroMovies[index];
                    final posterUrl = movie.posterUrl ?? '';

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: GestureDetector(
                        onTap: () => _showDiscoverMovieDetails(movie),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.26),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (posterUrl.isNotEmpty)
                                  Image.network(
                                    posterUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _emptyDiscoverPoster(),
                                  )
                                else
                                  ColoredBox(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: _emptyDiscoverPoster(),
                                  ),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.08),
                                        Colors.black.withValues(alpha: 0.82),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 12,
                                  top: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.17),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.34),
                                      ),
                                    ),
                                    child: Text(
                                      t('home_featured_label'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: accent,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 12,
                                  top: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.45,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      movie.voteAverage > 0
                                          ? 'TMDB ${movie.voteAverage.toStringAsFixed(1)}'
                                          : t('catalog_year_unknown'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 14,
                                  right: 14,
                                  bottom: 14,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        movie.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        movie.year.isEmpty ? '-' : movie.year,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.white.withValues(
                                                alpha: 0.88,
                                              ),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(heroMovies.length, (index) {
                  final active = _homeCarouselIndex == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? accent : colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ],
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(
                t('drawer_genres'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t('drawer_all_genres')),
                      selected: _selectedDiscoverGenreId == null,
                      selectedColor: accent.withValues(alpha: 0.2),
                      onSelected: (_) {
                        setState(() {
                          _selectedDiscoverGenreId = null;
                        });
                        _tabController.animateTo(1);
                      },
                    ),
                  ),
                  ...homeGenreEntries.map(
                    (genreEntry) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(genreEntry.value),
                        selected: _selectedDiscoverGenreId == genreEntry.key,
                        selectedColor: accent.withValues(alpha: 0.2),
                        onSelected: (_) {
                          setState(() {
                            _selectedDiscoverGenreId = genreEntry.key;
                          });
                          _tabController.animateTo(1);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('home_popular_title'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (hasTmdbKey)
                    TextButton(
                      onPressed: () => _goToTab(1),
                      child: Text(t('home_see_all')),
                    ),
                ],
              ),
            ),
            if (!hasTmdbKey || popularMovies.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      t('discover_feed_empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 252,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: popularMovies.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final movie = popularMovies[index];
                    return SizedBox(
                      width: 154,
                      child: GestureDetector(
                        onTap: () => _showDiscoverMovieDetails(movie),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(18),
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _SearchPoster(
                                        posterUrl: movie.posterUrl,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.62,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.star_rounded,
                                                size: 12,
                                                color: Color(0xFFFFB322),
                                              ),
                                              const SizedBox(width: 2),
                                              Text(
                                                movie.voteAverage > 0
                                                    ? movie.voteAverage
                                                          .toStringAsFixed(1)
                                                    : '-',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      movie.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      movie.year.isEmpty ? '-' : movie.year,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (homeGenreEntries.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...homeGenreEntries.take(2).map((genreEntry) {
                final genreMovies = _discoverMovies
                    .where(
                      (movie) =>
                          movie.genreIds.contains(genreEntry.key) &&
                          !highlightedIds.contains(movie.tmdbId),
                    )
                    .take(10)
                    .toList();
                if (genreMovies.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                genreEntry.value,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedDiscoverGenreId = genreEntry.key;
                                });
                                _goToTab(1);
                              },
                              child: Text(t('home_see_all')),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 210,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: genreMovies.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final movie = genreMovies[index];
                            return SizedBox(
                              width: 130,
                              child: GestureDetector(
                                onTap: () => _showDiscoverMovieDetails(movie),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: _SearchPoster(
                                          posterUrl: movie.posterUrl,
                                          width: double.infinity,
                                          height: double.infinity,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      movie.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWatchlistTab(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final watchlist = _sortedWatchlistMovies();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${t('watchlist_title')} (${watchlist.length})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                tooltip: t('select_sort'),
                onPressed: _openWatchlistSortModal,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: watchlist.isEmpty
                ? Center(
                    child: Text(
                      t('watchlist_empty'),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: watchlist.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final movie = watchlist[index];
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: ListTile(
                          onTap: () => _showWatchlistMovieDetails(movie),
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
                          subtitle: Text(t('watchlist_subtitle')),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _homeIconButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Icon(icon, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topBg = isDark ? const Color(0xFF131932) : const Color(0xFFEFF4FB);
    final bottomBg = isDark ? const Color(0xFF0A0F1F) : const Color(0xFFE7EEF8);

    return Scaffold(
      appBar: (_currentTab == 0 || _currentTab == 4)
          ? null
          : AppBar(
              title: Text(
                switch (_currentTab) {
                  1 => t('tab_discover'),
                  2 => t('tab_watched'),
                  3 => t('watchlist_title'),
                  _ => t('app_brand'),
                },
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              actions: [
                if (_currentTab == 2)
                  IconButton(
                    tooltip: t('select_sort'),
                    onPressed: _openWatchedSortModal,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                const SizedBox(width: 4),
              ],
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
              left: -95,
              top: -60,
              child: _backgroundBubble(
                size: 240,
                color: const Color(0xFF1ED2E8).withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              right: -70,
              top: 150,
              child: _backgroundBubble(
                size: 180,
                color: const Color(0xFF6B72FF).withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              right: -70,
              bottom: -45,
              child: _backgroundBubble(
                size: 210,
                color: const Color(0xFF1ED2E8).withValues(alpha: 0.09),
              ),
            ),
            TabBarView(
              controller: _tabController,
              children: [
                _buildHomeTab(context),
                _buildDiscoverTab(context),
                _buildWatchedTab(context),
                _buildWatchlistTab(context),
                const SettingsPage(),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: isDark ? 0.78 : 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                _BottomTabItem(
                  icon: Icons.home_rounded,
                  selected: _currentTab == 0,
                  onTap: () => _goToTab(0),
                ),
                _BottomTabItem(
                  icon: Icons.search_rounded,
                  selected: _currentTab == 1,
                  onTap: () => _goToTab(1),
                ),
                _BottomTabItem(
                  icon: Icons.movie_filter_rounded,
                  selected: _currentTab == 2,
                  onTap: () => _goToTab(2),
                ),
                _BottomTabItem(
                  icon: Icons.bookmark_rounded,
                  selected: _currentTab == 3,
                  onTap: () => _goToTab(3),
                ),
                _BottomTabItem(
                  icon: Icons.person_rounded,
                  selected: _currentTab == 4,
                  onTap: () => _goToTab(4),
                ),
              ],
            ),
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

class _CatalogPreviewData {
  final String title;
  final String year;
  final String? posterUrl;
  final String genre;
  final String director;
  final String runtime;
  final String plot;
  final double? imdbRating;
  final String rottenTomatoesRating;
  final double? tmdbRating;
  final String imdbId;

  const _CatalogPreviewData({
    required this.title,
    this.year = '',
    this.posterUrl,
    this.genre = '',
    this.director = '',
    this.runtime = '',
    this.plot = '',
    this.imdbRating,
    this.rottenTomatoesRating = '',
    this.tmdbRating,
    this.imdbId = '',
  });

  _CatalogPreviewData copyWith({
    String? title,
    String? year,
    String? posterUrl,
    String? genre,
    String? director,
    String? runtime,
    String? plot,
    double? imdbRating,
    String? rottenTomatoesRating,
    double? tmdbRating,
    String? imdbId,
  }) {
    return _CatalogPreviewData(
      title: title ?? this.title,
      year: year ?? this.year,
      posterUrl: posterUrl ?? this.posterUrl,
      genre: genre ?? this.genre,
      director: director ?? this.director,
      runtime: runtime ?? this.runtime,
      plot: plot ?? this.plot,
      imdbRating: imdbRating ?? this.imdbRating,
      rottenTomatoesRating: rottenTomatoesRating ?? this.rottenTomatoesRating,
      tmdbRating: tmdbRating ?? this.tmdbRating,
      imdbId: imdbId ?? this.imdbId,
    );
  }
}

class _CatalogMoviePreviewPage extends StatelessWidget {
  final _CatalogPreviewData initialData;
  final Future<_CatalogPreviewData> detailsFuture;
  final String primaryActionLabel;
  final bool primaryActionEnabled;
  final Future<void> Function(_CatalogPreviewData data)? onPrimaryAction;
  final Future<void> Function(_CatalogPreviewData data)? onFavoriteTap;

  const _CatalogMoviePreviewPage({
    required this.initialData,
    required this.detailsFuture,
    required this.primaryActionLabel,
    required this.primaryActionEnabled,
    this.onPrimaryAction,
    this.onFavoriteTap,
  });

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    const primaryAction = Color(0xFFFFB322);

    return Scaffold(
      body: FutureBuilder<_CatalogPreviewData>(
        future: detailsFuture,
        initialData: initialData,
        builder: (context, snapshot) {
          final data = snapshot.data ?? initialData;
          final posterUrl = (data.posterUrl ?? '').trim();
          final colorScheme = Theme.of(context).colorScheme;
          final metaTextStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.82),
            fontWeight: FontWeight.w600,
          );

          return Stack(
            children: [
              Positioned.fill(
                child: posterUrl.isNotEmpty
                    ? Image.network(
                        posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                        ),
                      )
                    : ColoredBox(color: colorScheme.surfaceContainerHighest),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(color: Colors.black.withValues(alpha: 0.5)),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.2),
                        const Color(0xFF0E1020).withValues(alpha: 0.84),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                        child: Row(
                          children: [
                            _previewTopButton(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onTap: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            Expanded(
                              flex: 5,
                              child: Text(
                                data.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            const Spacer(),
                            if (onFavoriteTap != null)
                              _previewTopButton(
                                icon: Icons.bookmark_add_rounded,
                                onTap: () async {
                                  await onFavoriteTap!.call(data);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                              )
                            else
                              const SizedBox(width: 38, height: 38),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 232,
                                height: 332,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.48,
                                      ),
                                      blurRadius: 32,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: posterUrl.isNotEmpty
                                    ? Image.network(
                                        posterUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _previewPosterFallback(context),
                                      )
                                    : _previewPosterFallback(context),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Center(
                              child: Wrap(
                                spacing: 14,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (data.year.isNotEmpty) ...[
                                    const Icon(
                                      Icons.calendar_month_outlined,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                    Text(data.year, style: metaTextStyle),
                                  ],
                                  if (data.runtime.isNotEmpty) ...[
                                    const Icon(
                                      Icons.schedule_rounded,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                    Text(data.runtime, style: metaTextStyle),
                                  ],
                                  if (data.genre.isNotEmpty) ...[
                                    const Icon(
                                      Icons.local_movies_outlined,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                    Text(data.genre, style: metaTextStyle),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Center(
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  if (data.imdbRating != null)
                                    _previewSourceBadge(
                                      context: context,
                                      icon: FontAwesomeIcons.imdb,
                                      value: data.imdbRating!.toStringAsFixed(
                                        1,
                                      ),
                                      background: const Color(0xFFF5C74C),
                                      foreground: const Color(0xFF3A2A00),
                                    )
                                  else if (data.tmdbRating != null)
                                    _previewSourceBadge(
                                      context: context,
                                      icon: Icons.star_rounded,
                                      value: data.tmdbRating!.toStringAsFixed(
                                        1,
                                      ),
                                      background: const Color(0xFFFFB322),
                                      foreground: const Color(0xFF3A2A00),
                                    ),
                                  if (data.rottenTomatoesRating.isNotEmpty)
                                    _previewSourceBadge(
                                      context: context,
                                      useRottenLogo: true,
                                      value: data.rottenTomatoesRating,
                                      background: const Color(0x88E6463D),
                                      foreground: Colors.white,
                                    ),
                                ],
                              ),
                            ),
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) ...[
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    t('catalog_loading_details'),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.88,
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: primaryActionEnabled
                                        ? () async {
                                            if (onPrimaryAction != null) {
                                              await onPrimaryAction!(data);
                                              return;
                                            }
                                            if (context.mounted) {
                                              Navigator.pop(context, true);
                                            }
                                          }
                                        : null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: primaryAction,
                                      foregroundColor: const Color(0xFF352300),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: Icon(
                                      primaryActionEnabled
                                          ? Icons.playlist_add_rounded
                                          : Icons.check_rounded,
                                    ),
                                    label: Text(primaryActionLabel),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _previewRoundAction(
                                  icon: Icons.ios_share_rounded,
                                  onTap: () =>
                                      _shareImdbLink(context, data.imdbId),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              t('plot'),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              data.plot.isEmpty ? '-' : data.plot,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    height: 1.4,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            if (data.director.isNotEmpty)
                              _previewInfoRow(
                                context,
                                t('director'),
                                data.director,
                              ),
                            if (data.genre.isNotEmpty)
                              _previewInfoRow(context, t('genre'), data.genre),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _shareImdbLink(BuildContext context, String imdbId) async {
    final trimmedId = imdbId.trim();
    if (trimmedId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.text(context, 'share_no_imdb_link'))),
      );
      return;
    }
    await Share.share('https://www.imdb.com/title/$trimmedId/');
  }

  Widget _previewTopButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _previewRoundAction({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFF2A3250).withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Icon(icon, color: const Color(0xFF1ED2E8), size: 20),
      ),
    );
  }

  Widget _previewSourceBadge({
    required BuildContext context,
    IconData? icon,
    bool useRottenLogo = false,
    required String value,
    required Color background,
    required Color foreground,
  }) {
    final resolvedIcon = icon ?? Icons.circle;
    final isFontAwesome = resolvedIcon.fontPackage == 'font_awesome_flutter';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (useRottenLogo)
            const _RottenTomatoMark(size: 13)
          else if (isFontAwesome)
            FaIcon(resolvedIcon, size: 13, color: foreground)
          else
            Icon(resolvedIcon, size: 15, color: foreground),
          const SizedBox(width: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewPosterFallback(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surfaceContainerHighest,
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 52,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _previewInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.92),
        ),
      ),
    );
  }
}

class _QuickMovieRatingPage extends StatefulWidget {
  final _CatalogPreviewData data;
  final double initialRating;
  final String actionLabel;

  const _QuickMovieRatingPage({
    required this.data,
    required this.initialRating,
    required this.actionLabel,
  });

  @override
  State<_QuickMovieRatingPage> createState() => _QuickMovieRatingPageState();
}

class _QuickMovieRatingPageState extends State<_QuickMovieRatingPage> {
  late double _rating;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating.clamp(0.5, 5.0);
  }

  String _formatRating(double value) {
    final raw = value.toStringAsFixed(1);
    final languageCode = AppSettingsScope.of(context).languageCode;
    if (languageCode.toLowerCase().startsWith('de')) {
      return raw.replaceAll('.', ',');
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: (widget.data.posterUrl ?? '').trim().isNotEmpty
                ? Image.network(
                    widget.data.posterUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        ColoredBox(color: colorScheme.surfaceContainerHighest),
                  )
                : ColoredBox(color: colorScheme.surfaceContainerHighest),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(color: Colors.black.withValues(alpha: 0.62)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _SearchPoster(
                                posterUrl: widget.data.posterUrl,
                                width: 80,
                                height: 118,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.data.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (widget.data.year.isNotEmpty)
                                    Text(
                                      widget.data.year,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.white70),
                                    ),
                                  if (widget.data.imdbRating != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const FaIcon(
                                          FontAwesomeIcons.imdb,
                                          size: 12,
                                          color: Color(0xFFF5C74C),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          widget.data.imdbRating!
                                              .toStringAsFixed(1),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  if (widget
                                      .data
                                      .rottenTomatoesRating
                                      .isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const _RottenTomatoMark(size: 12),
                                        const SizedBox(width: 4),
                                        Text(
                                          widget.data.rottenTomatoesRating,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          AppStrings.text(context, 'personal_rating'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 12),
                        RatingBar.builder(
                          initialRating: _rating,
                          minRating: 0.5,
                          allowHalfRating: true,
                          updateOnDrag: true,
                          itemCount: 5,
                          itemSize: 44,
                          unratedColor: Colors.white24,
                          itemPadding: const EdgeInsets.symmetric(
                            horizontal: 2,
                          ),
                          itemBuilder: (context, _) => const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFB322),
                          ),
                          onRatingUpdate: (value) {
                            setState(() {
                              _rating = value;
                            });
                          },
                        ),
                        Text(
                          '${_formatRating(_rating)} / ${_formatRating(5.0)}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFFFFB322),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, _rating),
                            child: Text(widget.actionLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

class _BottomTabItem extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _BottomTabItem({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = const Color(0xFF1ED2E8);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? accent : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RottenTomatoMark extends StatelessWidget {
  final double size;

  const _RottenTomatoMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: size * 0.12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE6463D),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: size * 0.32,
            child: Container(
              width: size * 0.38,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: const Color(0xFF72C23D),
                borderRadius: BorderRadius.circular(size * 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortOption<T> {
  final T value;
  final String label;

  const _SortOption(this.value, this.label);
}
