class Movie {
  final int? id;
  final String title;
  final double rating;
  final String comment;
  final String imagePath;

  Movie(this.id, this.title, this.rating, this.comment, this.imagePath);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'rating': rating,
      'comment': comment,
      'image_path': imagePath,
    };
  }

  factory Movie.fromMap(Map<String, dynamic> map) {
    return Movie(
      map['id'] as int?,
      map['title'] as String,
      (map['rating'] as num).toDouble(),
      map['comment'] as String,
      map['image_path'] as String,
    );
  }
}
