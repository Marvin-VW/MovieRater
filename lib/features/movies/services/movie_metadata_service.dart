import 'dart:convert';

import 'package:http/http.dart' as http;

class MovieMetadata {
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
    );
  }

  static Future<MovieMetadata?> fetchMovieMetadataByImdbId(
    String imdbId, {
    required String omdbApiKey,
    String? tmdbApiKey,
  }) async {
    final trimmedImdbId = imdbId.trim();
    final trimmedApiKey = omdbApiKey.trim();
    final trimmedTmdbApiKey = tmdbApiKey?.trim() ?? '';
    if (trimmedImdbId.isEmpty || trimmedApiKey.isEmpty) return null;

    final uri = Uri.parse(
      'https://www.omdbapi.com/?apikey=$trimmedApiKey&i=$trimmedImdbId',
    );
    return _fetchMovieMetadataFromUri(uri, tmdbApiKey: trimmedTmdbApiKey);
  }

  static Future<List<MovieSearchResult>> searchMovies(
    String query, {
    required String omdbApiKey,
  }) async {
    final trimmedQuery = query.trim();
    final trimmedApiKey = omdbApiKey.trim();
    if (trimmedQuery.isEmpty || trimmedApiKey.isEmpty) {
      return const [];
    }

    final encodedQuery = Uri.encodeQueryComponent(trimmedQuery);
    final uri = Uri.parse(
      'https://www.omdbapi.com/?apikey=$trimmedApiKey&s=$encodedQuery&type=movie',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return const [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if ((data['Response'] as String?) != 'True') return const [];

    final search = data['Search'];
    if (search is! List) return const [];

    final results = <MovieSearchResult>[];
    for (final item in search) {
      if (item is! Map) continue;
      final title = _sanitize(item['Title']);
      final year = _sanitize(item['Year']);
      final imdbId = _sanitize(item['imdbID']);
      if (title == null || year == null || imdbId == null) continue;
      results.add(
        MovieSearchResult(
          imdbId: imdbId,
          title: title,
          year: year,
          posterUrl: _sanitize(item['Poster']),
        ),
      );
    }
    return results;
  }

  static Future<List<DiscoverMovie>> discoverMovies({
    required String tmdbApiKey,
  }) async {
    final trimmedApiKey = tmdbApiKey.trim();
    if (trimmedApiKey.isEmpty) return const [];

    final uri = Uri.parse(
      'https://api.themoviedb.org/3/discover/movie?api_key=$trimmedApiKey'
      '&sort_by=popularity.desc&vote_count.gte=300&include_adult=false&page=1',
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
  }) async {
    final trimmedApiKey = tmdbApiKey.trim();
    if (trimmedApiKey.isEmpty) return null;

    final uri = Uri.parse(
      'https://api.themoviedb.org/3/movie/$tmdbId?api_key=$trimmedApiKey'
      '&append_to_response=credits,external_ids',
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

    var posterUrl = _sanitize(data['Poster']);
    final titleForPoster = posterSearchTitle ?? _sanitize(data['Title']);
    if (posterUrl == null &&
        tmdbApiKey.isNotEmpty &&
        titleForPoster != null &&
        titleForPoster.isNotEmpty) {
      posterUrl = await fetchPosterFromTmdb(titleForPoster, apiKey: tmdbApiKey);
    }

    return MovieMetadata(
      imdbId: _sanitize(data['imdbID']),
      posterUrl: posterUrl,
      year: _sanitize(data['Year']),
      genre: _sanitize(data['Genre']),
      director: _sanitize(data['Director']),
      runtime: _sanitize(data['Runtime']),
      plot: _sanitize(data['Plot']),
      imdbRating: _parseDouble(data['imdbRating']),
      rottenTomatoesRating: rottenTomatoes,
    );
  }

  static Future<String?> fetchPosterFromTmdb(
    String title, {
    required String apiKey,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedApiKey = apiKey.trim();
    if (trimmedTitle.isEmpty || trimmedApiKey.isEmpty) return null;

    final query = Uri.encodeQueryComponent(trimmedTitle);
    final uri = Uri.parse(
      'https://api.themoviedb.org/3/search/movie?api_key=$trimmedApiKey&query=$query',
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
}
