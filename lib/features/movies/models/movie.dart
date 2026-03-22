class Movie {
  final int? id;
  final String title;
  final double rating;
  final String comment;
  final String imagePath;
  final String posterUrl;
  final String year;
  final String genre;
  final String director;
  final String runtime;
  final String watchedAt;
  final String watchPlatform;
  final double? imdbRating;
  final String rottenTomatoesRating;
  final String imdbId;
  final String category;

  const Movie({
    this.id,
    required this.title,
    required this.rating,
    required this.comment,
    required this.imagePath,
    this.posterUrl = '',
    this.year = '',
    this.genre = '',
    this.director = '',
    this.runtime = '',
    this.watchedAt = '',
    this.watchPlatform = '',
    this.imdbRating,
    this.rottenTomatoesRating = '',
    this.imdbId = '',
    this.category = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'rating': rating,
      'comment': comment,
      'image_path': imagePath,
      'poster_url': posterUrl,
      'year': year,
      'genre': genre,
      'director': director,
      'runtime': runtime,
      'watched_at': watchedAt,
      'watch_platform': watchPlatform,
      'imdb_rating': imdbRating,
      'rotten_tomatoes_rating': rottenTomatoesRating,
      'imdb_id': imdbId,
      'category': category,
    };
  }

  factory Movie.fromMap(Map<String, dynamic> map) {
    return Movie(
      id: map['id'] as int?,
      title: (map['title'] as String?) ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0,
      comment: (map['comment'] as String?) ?? '',
      imagePath: (map['image_path'] as String?) ?? '',
      posterUrl: (map['poster_url'] as String?) ?? '',
      year: (map['year'] as String?) ?? '',
      genre: (map['genre'] as String?) ?? '',
      director: (map['director'] as String?) ?? '',
      runtime: (map['runtime'] as String?) ?? '',
      watchedAt: (map['watched_at'] as String?) ?? '',
      watchPlatform: (map['watch_platform'] as String?) ?? '',
      imdbRating: (map['imdb_rating'] as num?)?.toDouble(),
      rottenTomatoesRating: (map['rotten_tomatoes_rating'] as String?) ?? '',
      imdbId: (map['imdb_id'] as String?) ?? '',
      category: (map['category'] as String?) ?? '',
    );
  }
}
