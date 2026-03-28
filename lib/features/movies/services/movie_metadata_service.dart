import 'dart:convert';

import 'package:http/http.dart' as http;

class MovieMetadata {
  final String? title;
  final String? imdbId;
  final String? posterUrl;
  final String? year;
  final String? genre;
  final String? director;
  final String? runtime;
  final String? plot;
  final double? imdbRating;
  final String? rottenTomatoesRating;

  const MovieMetadata({
    this.title,
    this.imdbId,
    this.posterUrl,
    this.year,
    this.genre,
    this.director,
    this.runtime,
    this.plot,
    this.imdbRating,
    this.rottenTomatoesRating,
  });
}

class MovieSearchResult {
  final String imdbId;
  final String title;
  final String year;
  final String? posterUrl;

  const MovieSearchResult({
    required this.imdbId,
    required this.title,
    required this.year,
    this.posterUrl,
  });
}

class DiscoverMovie {
  final int tmdbId;
  final String title;
  final String year;
  final String? posterUrl;
  final String overview;
  final double voteAverage;
  final double popularity;
  final List<int> genreIds;

  const DiscoverMovie({
    required this.tmdbId,
    required this.title,
    required this.year,
    this.posterUrl,
    this.overview = '',
    this.voteAverage = 0,
    this.popularity = 0,
    this.genreIds = const [],
  });
}

class TmdbMovieDetails {
  final int tmdbId;
  final String title;
  final String year;
  final String? posterUrl;
  final String overview;
  final String genre;
  final String director;
  final String runtime;
  final String imdbId;

  const TmdbMovieDetails({
    required this.tmdbId,
    required this.title,
    required this.year,
    this.posterUrl,
    this.overview = '',
    this.genre = '',
    this.director = '',
    this.runtime = '',
    this.imdbId = '',
  });
}

class MovieMetadataService {
  static Future<bool> validateOmdbKey(String apiKey) async {
    final trimmedApiKey = apiKey.trim();
    if (trimmedApiKey.isEmpty) return false;

    final uri = Uri.parse(
      'https://www.omdbapi.com/?apikey=$trimmedApiKey&t=Inception',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return false;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['Response'] as String?) == 'True';
  }

  static Future<bool> validateTmdbKey(String apiKey) async {
    final trimmedApiKey = apiKey.trim();
    if (trimmedApiKey.isEmpty) return false;

    final uri = Uri.parse(
      'https://api.themoviedb.org/3/authentication?api_key=$trimmedApiKey',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return false;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['success'] == true;
  }

  static Future<MovieMetadata?> fetchMovieMetadata(
    String title, {
    required String omdbApiKey,
    String? tmdbApiKey,
    String languageCode = 'en',
  }) async {
    final trimmedTitle = title.trim();
    final trimmedApiKey = omdbApiKey.trim();
    final trimmedTmdbApiKey = tmdbApiKey?.trim() ?? '';
    if (trimmedTitle.isEmpty || trimmedApiKey.isEmpty) return null;

    final query = Uri.encodeQueryComponent(trimmedTitle);
    final uri = Uri.parse(
      'https://www.omdbapi.com/?apikey=$trimmedApiKey&t=$query',
    );
    return _fetchMovieMetadataFromUri(
      uri,
      tmdbApiKey: trimmedTmdbApiKey,
      posterSearchTitle: trimmedTitle,
      languageCode: languageCode,
    );
  }

  static Future<MovieMetadata?> fetchMovieMetadataByImdbId(
    String imdbId, {
    required String omdbApiKey,
    String? tmdbApiKey,
    String languageCode = 'en',
  }) async {
    final trimmedImdbId = imdbId.trim();
    final trimmedApiKey = omdbApiKey.trim();
    final trimmedTmdbApiKey = tmdbApiKey?.trim() ?? '';
    if (trimmedImdbId.isEmpty || trimmedApiKey.isEmpty) return null;

    final uri = Uri.parse(
      'https://www.omdbapi.com/?apikey=$trimmedApiKey&i=$trimmedImdbId',
    );
    return _fetchMovieMetadataFromUri(
      uri,
      tmdbApiKey: trimmedTmdbApiKey,
      languageCode: languageCode,
    );
  }

  static Future<List<MovieSearchResult>> searchMovies(
    String query, {
    required String omdbApiKey,
    String? tmdbApiKey,
    String languageCode = 'en',
  }) async {
    final trimmedQuery = query.trim();
    final trimmedApiKey = omdbApiKey.trim();
    final trimmedTmdbApiKey = tmdbApiKey?.trim() ?? '';
    if (trimmedQuery.isEmpty || trimmedApiKey.isEmpty) {
      return const [];
    }

    final results = <MovieSearchResult>[];
    final seenImdbIds = <String>{};
    final encodedQuery = Uri.encodeQueryComponent(trimmedQuery);

    for (var page = 1; page <= 2; page++) {
      final uri = Uri.parse(
        'https://www.omdbapi.com/?apikey=$trimmedApiKey&s=$encodedQuery&page=$page',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) break;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if ((data['Response'] as String?) != 'True') {
        if (page == 1) {
          break;
        }
        break;
      }

      final search = data['Search'];
      if (search is! List || search.isEmpty) break;

      for (final item in search) {
        if (item is! Map) continue;
        final title = _sanitize(item['Title']);
        final year = _sanitize(item['Year']);
        final imdbId = _sanitize(item['imdbID']);
        if (title == null || year == null || imdbId == null) continue;
        if (!seenImdbIds.add(imdbId)) continue;
        results.add(
          MovieSearchResult(
            imdbId: imdbId,
            title: title,
            year: year,
            posterUrl: _sanitize(item['Poster']),
          ),
        );
      }

      if (search.length < 10) break;
    }

    if (results.isNotEmpty || trimmedTmdbApiKey.isEmpty) {
      return results;
    }

    final tmdbFallback = await _searchMoviesViaTmdbFallback(
      trimmedQuery,
      tmdbApiKey: trimmedTmdbApiKey,
      languageCode: languageCode,
      seenImdbIds: seenImdbIds,
    );
    if (tmdbFallback.isNotEmpty) {
      results.addAll(tmdbFallback);
    }

    return results;
  }

  static Future<List<DiscoverMovie>> discoverMovies({
    required String tmdbApiKey,
    String languageCode = 'en',
  }) async {
    final trimmedApiKey = tmdbApiKey.trim();
    if (trimmedApiKey.isEmpty) return const [];
    final tmdbLanguage = _tmdbLanguageCode(languageCode);

    final uri = Uri.parse(
      'https://api.themoviedb.org/3/discover/movie?api_key=$trimmedApiKey'
      '&sort_by=popularity.desc&vote_count.gte=300&include_adult=false&page=1'
      '&language=$tmdbLanguage',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return const [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'];
    if (results is! List || results.isEmpty) return const [];

    final movies = <DiscoverMovie>[];
    for (final item in results.take(20)) {
      if (item is! Map) continue;

      final tmdbId = int.tryParse(item['id']?.toString() ?? '');
      final title = _sanitize(item['title']) ?? _sanitize(item['name']);
      if (tmdbId == null || title == null) continue;

      final releaseDate = _sanitize(item['release_date']) ?? '';
      final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
      final overview = _sanitize(item['overview']) ?? '';
      final voteAverage = _parseDouble(item['vote_average']) ?? 0;
      final popularity = _parseDouble(item['popularity']) ?? 0;
      final posterPath = _sanitize(item['poster_path']);
      final genreIdsRaw = item['genre_ids'];
      final genreIds = <int>[];
      if (genreIdsRaw is List) {
        for (final genreId in genreIdsRaw) {
          final parsed = int.tryParse(genreId.toString());
          if (parsed != null) {
            genreIds.add(parsed);
          }
        }
      }

      movies.add(
        DiscoverMovie(
          tmdbId: tmdbId,
          title: title,
          year: year,
          overview: overview,
          voteAverage: voteAverage,
          popularity: popularity,
          genreIds: genreIds,
          posterUrl: posterPath == null
              ? null
              : 'https://image.tmdb.org/t/p/w500$posterPath',
        ),
      );
    }

    return movies;
  }

  static Future<TmdbMovieDetails?> fetchTmdbMovieDetails(
    int tmdbId, {
    required String tmdbApiKey,
    String languageCode = 'en',
  }) async {
    final trimmedApiKey = tmdbApiKey.trim();
    if (trimmedApiKey.isEmpty) return null;
    final tmdbLanguage = _tmdbLanguageCode(languageCode);

    final uri = Uri.parse(
      'https://api.themoviedb.org/3/movie/$tmdbId?api_key=$trimmedApiKey'
      '&append_to_response=credits,external_ids&language=$tmdbLanguage',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final title = _sanitize(data['title']) ?? '';
    if (title.isEmpty) return null;

    final releaseDate = _sanitize(data['release_date']) ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

    String genre = '';
    final genresData = data['genres'];
    if (genresData is List) {
      final names = <String>[];
      for (final item in genresData) {
        if (item is! Map) continue;
        final name = _sanitize(item['name']);
        if (name != null) {
          names.add(name);
        }
      }
      genre = names.join(', ');
    }

    String director = '';
    final credits = data['credits'];
    if (credits is Map && credits['crew'] is List) {
      final crew = credits['crew'] as List;
      for (final item in crew) {
        if (item is! Map) continue;
        if (item['job'] == 'Director') {
          director = _sanitize(item['name']) ?? '';
          if (director.isNotEmpty) {
            break;
          }
        }
      }
    }

    final runtimeValue = _parseDouble(data['runtime']);
    final runtime = runtimeValue == null ? '' : '${runtimeValue.round()} min';

    String imdbId = '';
    final externalIds = data['external_ids'];
    if (externalIds is Map) {
      imdbId = _sanitize(externalIds['imdb_id']) ?? '';
    }

    final posterPath = _sanitize(data['poster_path']);

    return TmdbMovieDetails(
      tmdbId: tmdbId,
      title: title,
      year: year,
      genre: genre,
      director: director,
      runtime: runtime,
      imdbId: imdbId,
      overview: _sanitize(data['overview']) ?? '',
      posterUrl: posterPath == null
          ? null
          : 'https://image.tmdb.org/t/p/w500$posterPath',
    );
  }

  static Future<MovieMetadata?> _fetchMovieMetadataFromUri(
    Uri uri, {
    required String tmdbApiKey,
    String? posterSearchTitle,
    String languageCode = 'en',
  }) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if ((data['Response'] as String?) != 'True') return null;

    final ratings = data['Ratings'];
    String? rottenTomatoes;
    if (ratings is List) {
      for (final value in ratings) {
        if (value is Map && value['Source'] == 'Rotten Tomatoes') {
          rottenTomatoes = _sanitize(value['Value']);
          break;
        }
      }
    }

    final imdbId = _sanitize(data['imdbID']) ?? '';
    var title = _sanitize(data['Title']);
    var posterUrl = _sanitize(data['Poster']);
    var year = _sanitize(data['Year']);
    var genre = _sanitize(data['Genre']);
    var director = _sanitize(data['Director']);
    var runtime = _sanitize(data['Runtime']);
    var plot = _sanitize(data['Plot']);

    if (!languageCode.toLowerCase().startsWith('en') &&
        tmdbApiKey.isNotEmpty &&
        imdbId.isNotEmpty) {
      final localizedData = await _fetchLocalizedTmdbDataByImdbId(
        imdbId: imdbId,
        tmdbApiKey: tmdbApiKey,
        languageCode: languageCode,
      );
      title = localizedData['title'] ?? title;
      year = localizedData['year'] ?? year;
      genre = localizedData['genre'] ?? genre;
      director = localizedData['director'] ?? director;
      runtime = localizedData['runtime'] ?? runtime;
      plot = localizedData['plot'] ?? plot;
      posterUrl = localizedData['posterUrl'] ?? posterUrl;
    }

    final titleForPoster = posterSearchTitle ?? _sanitize(data['Title']);
    if (posterUrl == null &&
        tmdbApiKey.isNotEmpty &&
        titleForPoster != null &&
        titleForPoster.isNotEmpty) {
      posterUrl = await fetchPosterFromTmdb(
        titleForPoster,
        apiKey: tmdbApiKey,
        languageCode: languageCode,
      );
    }

    return MovieMetadata(
      title: title,
      imdbId: imdbId.isEmpty ? null : imdbId,
      posterUrl: posterUrl,
      year: year,
      genre: genre,
      director: director,
      runtime: runtime,
      plot: plot,
      imdbRating: _parseDouble(data['imdbRating']),
      rottenTomatoesRating: rottenTomatoes,
    );
  }

  static Future<MovieMetadata?> fetchLocalizedMetadataByImdbId(
    String imdbId, {
    required String tmdbApiKey,
    String languageCode = 'en',
  }) async {
    final localizedData = await _fetchLocalizedTmdbDataByImdbId(
      imdbId: imdbId,
      tmdbApiKey: tmdbApiKey,
      languageCode: languageCode,
    );
    if (localizedData.isEmpty) return null;

    return MovieMetadata(
      imdbId: imdbId,
      title: localizedData['title'],
      year: localizedData['year'],
      genre: localizedData['genre'],
      director: localizedData['director'],
      runtime: localizedData['runtime'],
      plot: localizedData['plot'],
      posterUrl: localizedData['posterUrl'],
    );
  }

  static Future<String?> fetchPosterFromTmdb(
    String title, {
    required String apiKey,
    String languageCode = 'en',
  }) async {
    final trimmedTitle = title.trim();
    final trimmedApiKey = apiKey.trim();
    if (trimmedTitle.isEmpty || trimmedApiKey.isEmpty) return null;
    final tmdbLanguage = _tmdbLanguageCode(languageCode);

    final query = Uri.encodeQueryComponent(trimmedTitle);
    final uri = Uri.parse(
      'https://api.themoviedb.org/3/search/movie?api_key=$trimmedApiKey&query=$query&language=$tmdbLanguage',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'];
    if (results is! List || results.isEmpty) return null;

    final first = results.first;
    if (first is! Map) return null;

    final posterPath = first['poster_path']?.toString() ?? '';
    if (posterPath.isEmpty || posterPath == 'null') return null;

    return 'https://image.tmdb.org/t/p/w500$posterPath';
  }

  static Future<Map<String, String?>> _fetchLocalizedTmdbDataByImdbId({
    required String imdbId,
    required String tmdbApiKey,
    required String languageCode,
  }) async {
    final trimmedImdbId = imdbId.trim();
    final trimmedApiKey = tmdbApiKey.trim();
    if (trimmedImdbId.isEmpty || trimmedApiKey.isEmpty) return const {};

    final tmdbLanguage = _tmdbLanguageCode(languageCode);
    final findUri = Uri.parse(
      'https://api.themoviedb.org/3/find/$trimmedImdbId?api_key=$trimmedApiKey'
      '&external_source=imdb_id&language=$tmdbLanguage',
    );

    final findResponse = await http
        .get(findUri)
        .timeout(const Duration(seconds: 12));
    if (findResponse.statusCode != 200) return const {};

    final findData = jsonDecode(findResponse.body) as Map<String, dynamic>;
    final movieResults = findData['movie_results'];
    if (movieResults is! List || movieResults.isEmpty) return const {};
    final firstMovie = movieResults.first;
    if (firstMovie is! Map) return const {};

    final tmdbId = int.tryParse(firstMovie['id']?.toString() ?? '');
    if (tmdbId == null) return const {};

    final detailsUri = Uri.parse(
      'https://api.themoviedb.org/3/movie/$tmdbId?api_key=$trimmedApiKey'
      '&append_to_response=credits&language=$tmdbLanguage',
    );
    final detailsResponse = await http
        .get(detailsUri)
        .timeout(const Duration(seconds: 12));
    if (detailsResponse.statusCode != 200) return const {};

    final details = jsonDecode(detailsResponse.body) as Map<String, dynamic>;
    final title = _sanitize(details['title']) ?? _sanitize(details['name']);
    final releaseDate = _sanitize(details['release_date']) ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null;
    final runtimeValue = _parseDouble(details['runtime']);
    final runtime = runtimeValue == null ? null : '${runtimeValue.round()} min';
    final posterPath = _sanitize(details['poster_path']);

    String? genre;
    final genresData = details['genres'];
    if (genresData is List && genresData.isNotEmpty) {
      final names = <String>[];
      for (final item in genresData) {
        if (item is! Map) continue;
        final name = _sanitize(item['name']);
        if (name != null) {
          names.add(name);
        }
      }
      if (names.isNotEmpty) {
        genre = names.join(', ');
      }
    }

    String? director;
    final credits = details['credits'];
    if (credits is Map && credits['crew'] is List) {
      final crew = credits['crew'] as List;
      for (final item in crew) {
        if (item is! Map) continue;
        if (item['job'] == 'Director') {
          director = _sanitize(item['name']);
          if (director != null) {
            break;
          }
        }
      }
    }

    return {
      'title': title,
      'year': year,
      'genre': genre,
      'director': director,
      'runtime': runtime,
      'plot': _sanitize(details['overview']),
      'posterUrl': posterPath == null
          ? null
          : 'https://image.tmdb.org/t/p/w500$posterPath',
    };
  }

  static Future<List<MovieSearchResult>> _searchMoviesViaTmdbFallback(
    String query, {
    required String tmdbApiKey,
    required String languageCode,
    required Set<String> seenImdbIds,
  }) async {
    final encodedQuery = Uri.encodeQueryComponent(query.trim());
    final tmdbLanguage = _tmdbLanguageCode(languageCode);
    final uri = Uri.parse(
      'https://api.themoviedb.org/3/search/movie?api_key=$tmdbApiKey'
      '&query=$encodedQuery&include_adult=false&language=$tmdbLanguage&page=1',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return const [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'];
    if (results is! List || results.isEmpty) return const [];

    final mapped = <MovieSearchResult>[];
    for (final item in results.take(8)) {
      if (item is! Map) continue;
      final tmdbId = int.tryParse(item['id']?.toString() ?? '');
      if (tmdbId == null) continue;

      final details = await fetchTmdbMovieDetails(
        tmdbId,
        tmdbApiKey: tmdbApiKey,
        languageCode: languageCode,
      );
      if (details == null || details.imdbId.isEmpty) continue;
      if (!seenImdbIds.add(details.imdbId)) continue;

      final title = details.title.trim();
      final year = details.year.trim();
      if (title.isEmpty || year.isEmpty) continue;

      mapped.add(
        MovieSearchResult(
          imdbId: details.imdbId,
          title: title,
          year: year,
          posterUrl: details.posterUrl,
        ),
      );
    }

    return mapped;
  }

  static double? _parseDouble(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'N/A') return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  static String? _sanitize(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'N/A') return null;
    return text;
  }

  static String _tmdbLanguageCode(String languageCode) {
    return languageCode.toLowerCase().startsWith('de') ? 'de-DE' : 'en-US';
  }
}
