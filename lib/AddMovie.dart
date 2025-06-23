import 'dart:io';
import 'package:flutter/material.dart';
import 'Movie.dart';
import 'Database.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class AddMoviePage extends StatefulWidget {
  final Movie? existingMovie;

  const AddMoviePage({super.key, this.existingMovie});

  @override
  State<AddMoviePage> createState() => _AddMoviePageState();
}

class _AddMoviePageState extends State<AddMoviePage> {
  final _titleController = TextEditingController();
  final _commentController = TextEditingController();
  double _rating = 2.5;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    if (widget.existingMovie != null) {
      _titleController.text = widget.existingMovie!.title;
      _commentController.text = widget.existingMovie!.comment;
      _rating = widget.existingMovie!.rating;
      if (widget.existingMovie!.imagePath.isNotEmpty) {
        _selectedImage = File(widget.existingMovie!.imagePath);
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      // Cropping starten
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: CropAspectRatio(ratioX: 1, ratioY: 1.2), // z.B. quadratisch
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Bild zuschneiden',
            toolbarColor: Colors.blue,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Bild zuschneiden',
            aspectRatioLockEnabled: true,
          )
        ],
      );

      if (cropped != null) {
        final dir = await getApplicationDocumentsDirectory();
        final fileName = p.basename(cropped.path);
        final savedPath = p.join(dir.path, fileName);
        final savedImage = await File(cropped.path).copy(savedPath);

        setState(() {
          _selectedImage = savedImage;
        });
      }
    }
  }

  Future<void> _saveMovie() async {
    if (_titleController.text.isEmpty) return;

    Movie movie = Movie(
      widget.existingMovie?.id,
      _titleController.text,
      _rating,
      _commentController.text,
      _selectedImage?.path ?? '',
    );

    await DatabaseHelper.saveMovie(movie);

    if (context.mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Film hinzufügen'),
        backgroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                _selectedImage != null
                    ? Image.file(
                  _selectedImage!,
                  height: MediaQuery.of(context).size.height * 0.3,
                )
                    : const Text('Kein Bild ausgewählt'),
                TextButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('Bild auswählen'),
                ),
                const SizedBox(height: 16),
                Center(child: _ratingBar()),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  maxLength: 50,
                  decoration: const InputDecoration(labelText: 'Filmtitel'),
                ),
                const SizedBox(height: 8),
                TextField(
                  maxLines: null,
                  maxLength: 100,
                  controller: _commentController,
                  decoration: const InputDecoration(labelText: 'Kommentar'),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: ElevatedButton(
              onPressed: _saveMovie,
              child: const Text('Speichern'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingBar() {
    return RatingBar.builder(
      initialRating: _rating,
      minRating: 0,
      direction: Axis.horizontal,
      allowHalfRating: true,
      unratedColor: Colors.amber.withAlpha(70),
      itemCount: 5,
      itemSize: 60.0,
      itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
      itemBuilder: (context, _) => const Icon(
        Icons.star,
        color: Colors.amber,
      ),
      onRatingUpdate: (rating) {
        setState(() {
          _rating = rating;
        });
      },
      updateOnDrag: true,
    );
  }
}
