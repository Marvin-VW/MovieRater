import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/movies/models/movie.dart';

enum MovieSortField { title, rating, watchedAt, category }

enum SortDirection { asc, desc }

enum DatabaseChangeType { insert, update, delete }

typedef DatabaseChangeListener = void Function(DatabaseChangeType changeType);

class DatabaseHelper {
  static Database? _db;
  static DatabaseChangeListener? _changeListener;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  static Future<Database> initDb() async {
    if (_db != null) return _db!;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'filme.db');

    _db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE movies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            rating REAL,
            comment TEXT,
            image_path TEXT,
            poster_url TEXT DEFAULT '',
            year TEXT DEFAULT '',
            genre TEXT DEFAULT '',
            director TEXT DEFAULT '',
            runtime TEXT DEFAULT '',
            watched_at TEXT DEFAULT '',
            watch_platform TEXT DEFAULT '',
            imdb_rating REAL,
            rotten_tomatoes_rating TEXT DEFAULT '',
            imdb_id TEXT DEFAULT '',
            category TEXT DEFAULT ''
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToV2(db);
        }
        if (oldVersion < 3) {
          await _migrateToV3(db);
        }
      },
    );

    return _db!;
  }

  static Future<void> _migrateToV2(Database db) async {
    await db.execute(
      "ALTER TABLE movies ADD COLUMN poster_url TEXT DEFAULT ''",
    );
    await db.execute("ALTER TABLE movies ADD COLUMN year TEXT DEFAULT ''");
    await db.execute("ALTER TABLE movies ADD COLUMN genre TEXT DEFAULT ''");
    await db.execute("ALTER TABLE movies ADD COLUMN director TEXT DEFAULT ''");
    await db.execute("ALTER TABLE movies ADD COLUMN runtime TEXT DEFAULT ''");
    await db.execute(
      "ALTER TABLE movies ADD COLUMN watched_at TEXT DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE movies ADD COLUMN watch_platform TEXT DEFAULT ''",
    );
    await db.execute('ALTER TABLE movies ADD COLUMN imdb_rating REAL');
    await db.execute(
      "ALTER TABLE movies ADD COLUMN rotten_tomatoes_rating TEXT DEFAULT ''",
    );
  }

  static Future<void> _migrateToV3(Database db) async {
    await db.execute("ALTER TABLE movies ADD COLUMN imdb_id TEXT DEFAULT ''");
    await db.execute("ALTER TABLE movies ADD COLUMN category TEXT DEFAULT ''");
  }

  static Future<List<Movie>> loadMovies({
    MovieSortField sortField = MovieSortField.rating,
    SortDirection direction = SortDirection.desc,
  }) async {
    final db = await database;

    final fieldName = switch (sortField) {
      MovieSortField.title => 'title',
      MovieSortField.watchedAt => 'watched_at',
      MovieSortField.rating => 'rating',
      MovieSortField.category => 'category',
    };

    final dir = direction == SortDirection.asc ? 'ASC' : 'DESC';

    final maps = await db.query(
      'movies',
      orderBy: '$fieldName $dir, rating DESC',
    );

    return maps.map(Movie.fromMap).toList();
  }

  static Future<void> deleteMovie(int id) async {
    final db = await database;
    await db.delete('movies', where: 'id = ?', whereArgs: [id]);
    _changeListener?.call(DatabaseChangeType.delete);
  }

  static Future<void> saveMovie(Movie movie) async {
    final db = await database;
    if (movie.id == null) {
      await db.insert('movies', movie.toMap());
      _changeListener?.call(DatabaseChangeType.insert);
      return;
    }

    await db.update(
      'movies',
      movie.toMap(),
      where: 'id = ?',
      whereArgs: [movie.id],
    );
    _changeListener?.call(DatabaseChangeType.update);
  }

  static Future<int> movieCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS count FROM movies');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> closeDb() async {
    if (_db == null) return;
    await _db!.close();
    _db = null;
  }

  static void setChangeListener(DatabaseChangeListener? listener) {
    _changeListener = listener;
  }

  static Future<bool> movieExists({
    String? imdbId,
    required String title,
    String? year,
    int? excludeId,
  }) async {
    final db = await database;
    final normalizedTitle = title.trim().toLowerCase();
    if (normalizedTitle.isEmpty) return false;

    final trimmedImdbId = imdbId?.trim() ?? '';
    if (trimmedImdbId.isNotEmpty) {
      final args = <Object>[trimmedImdbId];
      final whereParts = <String>['imdb_id = ?'];
      if (excludeId != null) {
        whereParts.add('id != ?');
        args.add(excludeId);
      }

      final byImdb = await db.query(
        'movies',
        columns: ['id'],
        where: whereParts.join(' AND '),
        whereArgs: args,
        limit: 1,
      );
      if (byImdb.isNotEmpty) return true;
    }

    final whereParts = <String>['LOWER(title) = ?'];
    final args = <Object>[normalizedTitle];
    final trimmedYear = year?.trim() ?? '';
    if (trimmedYear.isNotEmpty) {
      whereParts.add('year = ?');
      args.add(trimmedYear);
    }
    if (excludeId != null) {
      whereParts.add('id != ?');
      args.add(excludeId);
    }

    final byTitle = await db.query(
      'movies',
      columns: ['id'],
      where: whereParts.join(' AND '),
      whereArgs: args,
      limit: 1,
    );
    return byTitle.isNotEmpty;
  }
}
