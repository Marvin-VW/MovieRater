import 'dart:io';
import 'package:flutter/material.dart';
import 'Movie.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

class MovieListItem extends StatelessWidget {
  final Movie movie;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const MovieListItem({
    Key? key,
    required this.movie,
    required this.onDelete,
    required this.onEdit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white70,
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: movie.imagePath.isNotEmpty
                  ? Image.file(
                File(movie.imagePath),
                width: 100,
                height: 120,
                fit: BoxFit.cover,
              )
                  : Container(
                width: 100,
                height: 120,
                color: Colors.grey,
                child: const Icon(Icons.movie, size: 50, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10.0),
            Expanded(
              child: _MovieDescription(
                title: movie.title,
                rating: movie.rating,
                comment: movie.comment,
              ),
            ),
            PopupMenuButton<String>(
              color: Colors.white,
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Ändern'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Löschen'),
                ),
              ],
              icon: const Icon(Icons.more_vert, size: 20.0),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovieDescription extends StatelessWidget {
  final String title;
  final double rating;
  final String comment;

  const _MovieDescription({
    required this.title,
    required this.rating,
    required this.comment,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 20.0),
          ),
        ),
        const SizedBox(height: 4.0),
        _ratingBar(rating), // stays at the very left
        const SizedBox(height: 2.0),
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Text(
            comment.isNotEmpty ? comment : 'Kein Kommentar',
            style: const TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _ratingBar(double rating) {
    return RatingBar.builder(
      initialRating: rating,
      minRating: 0,
      direction: Axis.horizontal,
      allowHalfRating: true,
      unratedColor: Colors.amber.withAlpha(70),
      itemCount: 5,
      itemSize: 30.0,
      itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
      ignoreGestures: true,
      itemBuilder: (context, _) => const Icon(
        Icons.star,
        color: Colors.amber,
      ), onRatingUpdate: (double value) {  },
    );
  }
}
