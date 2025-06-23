import 'package:flutter/material.dart';
import 'Movie.dart';
import 'MovieListItem.dart';
import 'AddMovie.dart';
import 'Database.dart';
import 'Settings.dart';

class MovieListPage extends StatefulWidget {
  const MovieListPage({super.key});

  @override
  State<MovieListPage> createState() => _MovieListPageState();
}

class _MovieListPageState extends State<MovieListPage> {
  List<Movie> _movies = [];
  bool showMenu = false;

  @override
  void initState() {
    super.initState();

    _loadMovies(MovieSortField.rating, SortDirection.desc);
  }

  Future<void> _loadMovies(MovieSortField sortField, SortDirection direction) async {
    await DatabaseHelper.initDb();
    final movies = await DatabaseHelper.loadMovies(
      sortField: sortField,
      direction: direction,
    );
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
      _loadMovies(MovieSortField.rating, SortDirection.desc);
    }
  }

  Future<void> _editMovie(Movie movie) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddMoviePage(existingMovie: movie)),
    );
    if (result == true) {
      _loadMovies(MovieSortField.rating, SortDirection.desc);
    }
  }

  Future<void> _deleteMovie(int id) async {
    await DatabaseHelper.deleteMovie(id);
    _loadMovies(MovieSortField.rating, SortDirection.desc);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _movies.isEmpty
          ? const Center(child: Text('Noch keine Filme eingetragen.'))
          : ListView.builder(
        itemCount: _movies.length,
        itemBuilder: (context, index) {
          final movie = _movies[index];
          return MovieListItem(
            movie: movie,
            onEdit: () => _editMovie(movie),
            onDelete: () => _deleteMovie(movie.id!),
          );
        },
      ),
      floatingActionButton: Stack(
        alignment: Alignment.bottomRight,
        children: [
          if (showMenu)
            Padding(
              padding: const EdgeInsets.only(right: 8.0, bottom: 180.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildMenuItem("Rating: ASC", () {
                    setState(() {
                      _loadMovies(MovieSortField.rating, SortDirection.asc);
                      showMenu = false;
                    });
                  }),
                  const SizedBox(height: 8),
                  _buildMenuItem("Rating: DESC", () {
                    setState(() {
                      _loadMovies(MovieSortField.rating, SortDirection.desc);
                      showMenu = false;
                    });
                  }),
                  const SizedBox(height: 8),
                  _buildMenuItem("Last Watched", () {
                    setState(() {

                      showMenu = false;
                    });
                  }),
                ],
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton(
                backgroundColor: Colors.white70,
                onPressed: () {
                  setState(() {
                    showMenu = !showMenu;
                  });
                },
                child: Icon(showMenu ? Icons.close : Icons.menu),
                mini: true,
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                backgroundColor: Colors.white70,
                heroTag: 'settings',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SettingsPage()),
                  );
                },
                child: const Icon(Icons.settings),
                mini: true,
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                backgroundColor: Colors.white70,
                heroTag: 'add',
                onPressed: _addMovie,
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Text(text),
      ),
    );
  }
}