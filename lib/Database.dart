import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'Movie.dart';

enum MovieSortField {
  title,
  rating,
}

enum SortDirection {
  asc,
  desc,
}
class DatabaseHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  static Future<Database> initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'filme.db');
    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE movies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            rating REAL,
            comment TEXT,
            image_path TEXT
          )
        ''');
      },
    );
  }

  static Future<List<Movie>> loadMovies({
    MovieSortField sortField = MovieSortField.rating,
    SortDirection direction = SortDirection.desc,
  }) async {
    final db = await database;

    String fieldName;
    switch (sortField) {
      case MovieSortField.title:
        fieldName = 'title';
        break;
      case MovieSortField.rating:
        fieldName = 'rating';
        break;
    }

    final dir = direction == SortDirection.asc ? 'ASC' : 'DESC';
    final orderBy = '$fieldName $dir';

    final List<Map<String, dynamic>> maps = await db.query(
      'movies',
      orderBy: orderBy,
    );

    return maps.map((map) => Movie(
      map['id'],
      map['title'],
      map['rating'],
      map['comment'],
      map['image_path'],
    )).toList();
  }

  static Future<void> deleteMovie(int id) async {
    final db = await database;
    await db.delete('movies', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> saveMovie(Movie movie) async {
    final db = await database;
    if (movie.id == null) {
      await db.insert('movies', movie.toMap());
    } else {
      await db.update(
        'movies',
        movie.toMap(),
        where: 'id = ?',
        whereArgs: [movie.id],
      );
    }
  }
}
