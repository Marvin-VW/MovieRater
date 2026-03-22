import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../../../app/localization/app_strings.dart';
import '../models/movie.dart';

class MovieListItem extends StatelessWidget {
  final Movie movie;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const MovieListItem({
    super.key,
    required this.movie,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PosterImage(movie: movie),
              const SizedBox(width: 12),
              Expanded(child: _MovieDescription(movie: movie)),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                    return;
                  }
                  onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text(t('edit'))),
                  PopupMenuItem(value: 'delete', child: Text(t('delete'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  final Movie movie;

  const _PosterImage({required this.movie});

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (movie.imagePath.isNotEmpty && File(movie.imagePath).existsSync()) {
      imageWidget = Image.file(
        File(movie.imagePath),
        width: 82,
        height: 116,
        fit: BoxFit.cover,
      );
    } else if (movie.posterUrl.isNotEmpty) {
      imageWidget = Image.network(
        movie.posterUrl,
        width: 82,
        height: 116,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackPoster(context),
      );
    } else {
      imageWidget = _fallbackPoster(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: imageWidget,
    );
  }

  Widget _fallbackPoster(BuildContext context) {
    return Container(
      width: 82,
      height: 116,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie,
        size: 34,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _MovieDescription extends StatelessWidget {
  final Movie movie;

  const _MovieDescription({required this.movie});

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          movie.year.isNotEmpty
              ? '${movie.title} (${movie.year})'
              : movie.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        if (movie.genre.isNotEmpty || movie.director.isNotEmpty)
          Text(
            [
              movie.genre,
              movie.director,
            ].where((value) => value.isNotEmpty).join(' | '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 6),
        RatingBarIndicator(
          rating: movie.rating,
          itemBuilder: (context, _) =>
              const Icon(Icons.star, color: Colors.amber),
          itemCount: 5,
          itemSize: 18,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (movie.imdbRating != null)
              _ratingChip(
                label: 'IMDb ${movie.imdbRating!.toStringAsFixed(1)}',
              ),
            if (movie.rottenTomatoesRating.isNotEmpty)
              _ratingChip(label: 'RT ${movie.rottenTomatoesRating}'),
          ],
        ),
        const SizedBox(height: 6),
        if (movie.watchedAt.isNotEmpty || movie.watchPlatform.isNotEmpty)
          Text(
            [
              movie.watchedAt,
              movie.watchPlatform,
            ].where((value) => value.isNotEmpty).join(' • '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 6),
        Text(
          movie.comment.isNotEmpty ? movie.comment : t('no_comment'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _ratingChip({required String label}) {
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      label: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
