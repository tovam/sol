import Foundation
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1 as Int, to: sqlite3_destructor_type?.self)

struct File {
  let path: String
  let name: String
  let is_folder: Bool
  let modifiedAt: Double
  let size: Int64
}

enum FileSearchSort: String {
  case nameAscending = "name_asc"
  case nameDescending = "name_desc"
  case modifiedAscending = "modified_asc"
  case modifiedDescending = "modified_desc"
  case sizeAscending = "size_asc"
  case sizeDescending = "size_desc"

  var orderByClause: String {
    switch self {
    case .nameAscending:
      return "normalized_name ASC, path ASC"
    case .nameDescending:
      return "normalized_name DESC, path ASC"
    case .modifiedAscending:
      return "modified_at IS NULL ASC, modified_at ASC, normalized_name ASC, path ASC"
    case .modifiedDescending:
      return "modified_at IS NULL ASC, modified_at DESC, normalized_name ASC, path ASC"
    case .sizeAscending:
      return "file_size IS NULL ASC, file_size ASC, normalized_name ASC, path ASC"
    case .sizeDescending:
      return "file_size IS NULL ASC, file_size DESC, normalized_name ASC, path ASC"
    }
  }
}

class FileSearchIndex {
  static let shared = FileSearchIndex()
  
  private var db: OpaquePointer?
  private let dbPath: String
  private let queue = DispatchQueue(label: "com.ospfranco.sol.filesearch.index")
  
  init() {
    let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
    let appSupportDir = paths[0]
    let solDir = (appSupportDir as NSString).appendingPathComponent("Sol")
    
    // Create directory if it doesn't exist
    try? FileManager.default.createDirectory(atPath: solDir, withIntermediateDirectories: true)
    
    self.dbPath = (solDir as NSString).appendingPathComponent("filesearch.db")
    
    self.initializeDatabase()
  }
  
  private func initializeDatabase() {
    var openedDatabase: OpaquePointer?
    guard sqlite3_open(dbPath, &openedDatabase) == SQLITE_OK,
      let db = openedDatabase
    else {
      if let openedDatabase {
        sqlite3_close(openedDatabase)
      }
      return
    }
    self.db = db
      
    let createTableSQL = """
        CREATE TABLE IF NOT EXISTS files (
          path TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          normalized_name TEXT NOT NULL DEFAULT '',
          is_folder INTEGER NOT NULL,
          parent_path TEXT,
          modified_at REAL,
          file_size INTEGER,
          indexed_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE INDEX IF NOT EXISTS idx_name ON files(name);
        CREATE INDEX IF NOT EXISTS idx_parent ON files(parent_path);
    """
      
    guard executeSQL(createTableSQL, in: db) else {
      sqlite3_close(db)
      self.db = nil
      return
    }

    if !self.hasColumn("normalized_name", in: db) {
      guard executeSQL(
        "ALTER TABLE files ADD COLUMN normalized_name TEXT NOT NULL DEFAULT '';",
        in: db
      ) else {
        sqlite3_close(db)
        self.db = nil
        return
      }
    }

    if !self.hasColumn("modified_at", in: db) {
      guard executeSQL(
        "ALTER TABLE files ADD COLUMN modified_at REAL;",
        in: db
      ) else {
        sqlite3_close(db)
        self.db = nil
        return
      }
    }

    if !self.hasColumn("file_size", in: db) {
      guard executeSQL(
        "ALTER TABLE files ADD COLUMN file_size INTEGER;",
        in: db
      ) else {
        sqlite3_close(db)
        self.db = nil
        return
      }
    }

    queue.async { [weak self] in
      guard let self, let db = self.db else { return }
      guard self.backfillNormalizedNames(in: db) else { return }
      self.executeSQL(
        "CREATE INDEX IF NOT EXISTS idx_normalized_name "
          + "ON files(normalized_name, path);",
        in: db
      )
      self.scheduleMetadataBackfill(in: db, afterRowID: 0)
    }
  }

  @discardableResult
  private func executeSQL(_ sql: String, in db: OpaquePointer) -> Bool {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
    if let errorMessage {
      sqlite3_free(errorMessage)
    }
    return result == SQLITE_OK
  }

  private func hasColumn(_ columnName: String, in db: OpaquePointer) -> Bool {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA table_info(files);", -1, &statement, nil)
      == SQLITE_OK
    else {
      return false
    }
    defer { sqlite3_finalize(statement) }

    while sqlite3_step(statement) == SQLITE_ROW {
      guard let column = sqlite3_column_text(statement, 1) else { continue }
      if String(cString: column) == columnName {
        return true
      }
    }
    return false
  }

  private func normalizedSearchText(_ value: String) -> String {
    let locale = Locale(identifier: "en_US_POSIX")
    let normalized = value
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: locale
      )
      .lowercased(with: locale)
    return normalized.isEmpty ? value.lowercased(with: locale) : normalized
  }

  private func metadata(atPath path: String, isFolder: Bool) -> (
    modifiedAt: Double?,
    size: Int64?
  ) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    else {
      return (nil, nil)
    }

    let modifiedAt = (attributes[.modificationDate] as? Date)?
      .timeIntervalSince1970
    let size: Int64? = isFolder
      ? 0
      : (attributes[.size] as? NSNumber)?.int64Value
    return (modifiedAt, size)
  }

  private func backfillNormalizedNames(in db: OpaquePointer) -> Bool {
    var updateStatement: OpaquePointer?
    guard sqlite3_prepare_v2(
      db,
      "UPDATE files SET normalized_name = ? WHERE path = ?;",
      -1,
      &updateStatement,
      nil
    ) == SQLITE_OK else {
      return false
    }
    defer { sqlite3_finalize(updateStatement) }

    var lastRowID: Int64 = 0
    while true {
      var selectStatement: OpaquePointer?
      guard sqlite3_prepare_v2(
        db,
        """
        SELECT rowid, path, name
        FROM files
        WHERE normalized_name = '' AND rowid > ?
        ORDER BY rowid ASC
        LIMIT 500;
        """,
        -1,
        &selectStatement,
        nil
      ) == SQLITE_OK else {
        return false
      }
      sqlite3_bind_int64(selectStatement, 1, lastRowID)
      var batch: [(rowID: Int64, path: String, normalizedName: String)] = []
      while sqlite3_step(selectStatement) == SQLITE_ROW {
        guard
          let pathColumn = sqlite3_column_text(selectStatement, 1),
          let nameColumn = sqlite3_column_text(selectStatement, 2)
        else {
          continue
        }
        batch.append((
          rowID: sqlite3_column_int64(selectStatement, 0),
          path: String(cString: pathColumn),
          normalizedName: normalizedSearchText(String(cString: nameColumn))
        ))
      }
      sqlite3_finalize(selectStatement)
      guard !batch.isEmpty else { return true }

      guard executeSQL("BEGIN TRANSACTION;", in: db) else { return false }
      for entry in batch {
        sqlite3_bind_text(
          updateStatement,
          1,
          entry.normalizedName,
          -1,
          SQLITE_TRANSIENT
        )
        sqlite3_bind_text(updateStatement, 2, entry.path, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(updateStatement) == SQLITE_DONE else {
          sqlite3_reset(updateStatement)
          sqlite3_clear_bindings(updateStatement)
          executeSQL("ROLLBACK;", in: db)
          return false
        }
        sqlite3_reset(updateStatement)
        sqlite3_clear_bindings(updateStatement)
      }
      guard executeSQL("COMMIT;", in: db) else {
        executeSQL("ROLLBACK;", in: db)
        return false
      }
      lastRowID = batch[batch.count - 1].rowID
    }
  }

  private func scheduleMetadataBackfill(
    in db: OpaquePointer,
    afterRowID: Int64
  ) {
    queue.async { [weak self] in
      guard let self else { return }
      guard let nextRowID = self.backfillMetadataBatch(
        in: db,
        afterRowID: afterRowID
      ) else {
        return
      }
      self.scheduleMetadataBackfill(in: db, afterRowID: nextRowID)
    }
  }

  private func backfillMetadataBatch(
    in db: OpaquePointer,
    afterRowID: Int64
  ) -> Int64? {
    var selectStatement: OpaquePointer?
    guard sqlite3_prepare_v2(
      db,
      """
      SELECT rowid, path, is_folder
      FROM files
      WHERE (modified_at IS NULL OR file_size IS NULL) AND rowid > ?
      ORDER BY rowid ASC
      LIMIT 200;
      """,
      -1,
      &selectStatement,
      nil
    ) == SQLITE_OK else {
      return nil
    }
    sqlite3_bind_int64(selectStatement, 1, afterRowID)

    var batch: [(
      rowID: Int64,
      path: String,
      modifiedAt: Double?,
      size: Int64?
    )] = []
    while true {
      let result = sqlite3_step(selectStatement)
      if result == SQLITE_DONE { break }
      guard result == SQLITE_ROW,
        let pathColumn = sqlite3_column_text(selectStatement, 1)
      else {
        sqlite3_finalize(selectStatement)
        return nil
      }

      let path = String(cString: pathColumn)
      let isFolder = sqlite3_column_int(selectStatement, 2) != 0
      let metadata = metadata(atPath: path, isFolder: isFolder)
      batch.append((
        rowID: sqlite3_column_int64(selectStatement, 0),
        path: path,
        modifiedAt: metadata.modifiedAt,
        size: metadata.size
      ))
    }
    sqlite3_finalize(selectStatement)
    guard let nextRowID = batch.last?.rowID else { return nil }

    var updateStatement: OpaquePointer?
    guard sqlite3_prepare_v2(
      db,
      "UPDATE files SET modified_at = ?, file_size = ? WHERE path = ?;",
      -1,
      &updateStatement,
      nil
    ) == SQLITE_OK else {
      return nil
    }
    defer { sqlite3_finalize(updateStatement) }

    guard executeSQL("BEGIN TRANSACTION;", in: db) else { return nil }
    for entry in batch {
      if let modifiedAt = entry.modifiedAt {
        sqlite3_bind_double(updateStatement, 1, modifiedAt)
      } else {
        sqlite3_bind_null(updateStatement, 1)
      }
      if let size = entry.size {
        sqlite3_bind_int64(updateStatement, 2, size)
      } else {
        sqlite3_bind_null(updateStatement, 2)
      }
      sqlite3_bind_text(updateStatement, 3, entry.path, -1, SQLITE_TRANSIENT)
      guard sqlite3_step(updateStatement) == SQLITE_DONE else {
        sqlite3_reset(updateStatement)
        sqlite3_clear_bindings(updateStatement)
        executeSQL("ROLLBACK;", in: db)
        return nil
      }
      sqlite3_reset(updateStatement)
      sqlite3_clear_bindings(updateStatement)
    }
    guard executeSQL("COMMIT;", in: db) else {
      executeSQL("ROLLBACK;", in: db)
      return nil
    }
    return nextRowID
  }
  
  func indexPath(_ basePath: NSString) {
    queue.async { [weak self] in
      guard let self = self, let db = self.db else { return }
      self._indexPathIterative(basePath as String, db: db)
    }
  }

  func indexPaths(_ paths: [String]) {
    queue.async { [weak self] in
      guard let self = self, let db = self.db else { return }
      for path in paths {
        self._indexPathIterative(path, db: db)
      }
    }
  }

  func hasIndexedContent() -> Bool {
    var result = false
    queue.sync { [weak self] in
      guard let self = self, let db = self.db else { return }
      var statement: OpaquePointer?
      if sqlite3_prepare_v2(db, "SELECT 1 FROM files LIMIT 1;", -1, &statement, nil) == SQLITE_OK {
        result = sqlite3_step(statement) == SQLITE_ROW
        sqlite3_finalize(statement)
      }
    }
    return result
  }

  func removeIndexedPath(_ basePath: String) {
    queue.async { [weak self] in
      guard let self = self, let db = self.db else { return }
      let deleteSQL = "DELETE FROM files WHERE path LIKE ? || '%';"
      var statement: OpaquePointer?
      if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
        sqlite3_bind_text(statement, 1, basePath, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
      }
    }
  }

  func upsertFile(path: String, name: String, isFolder: Bool, parentPath: String) {
    queue.async { [weak self] in
      guard let self = self, let db = self.db else { return }
      self._insertOrUpdateFile(path: path, name: name, isFolder: isFolder, parentPath: parentPath, db: db)
    }
  }

  func removeFile(atPath path: String) {
    queue.async { [weak self] in
      guard let self = self, let db = self.db else { return }
      var statement: OpaquePointer?
      if sqlite3_prepare_v2(db, "DELETE FROM files WHERE path = ?;", -1, &statement, nil) == SQLITE_OK {
        sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
      }
    }
  }
  
  private func _indexPathIterative(_ rootPath: String, db: OpaquePointer) {
    let fileManager = FileManager.default
    let batchSize = 200
    var pendingDirs: [String] = [rootPath]
    var batchCount = 0

    sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

    while !pendingDirs.isEmpty {
      let currentDir = pendingDirs.removeFirst()

      guard let dirContents = try? fileManager.contentsOfDirectory(atPath: currentDir) else {
        continue
      }

      for item in dirContents {
        // Skip hidden files and folders
        if item.hasPrefix(".") {
          continue
        }

        let fullPath = (currentDir as NSString).appendingPathComponent(item)
        var isDir: ObjCBool = false

        guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else {
          continue
        }

        self._insertOrUpdateFile(path: fullPath, name: item, isFolder: isDir.boolValue, parentPath: currentDir, db: db)
        batchCount += 1

        if isDir.boolValue {
          pendingDirs.append(fullPath)
        }

        if batchCount >= batchSize {
          sqlite3_exec(db, "COMMIT;", nil, nil, nil)
          sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
          batchCount = 0
        }
      }
    }

    sqlite3_exec(db, "COMMIT;", nil, nil, nil)
  }

  private func _insertOrUpdateFile(path: String, name: String, isFolder: Bool, parentPath: String, db: OpaquePointer) {
    let metadata = metadata(atPath: path, isFolder: isFolder)
    let insertSQL = """
      INSERT OR REPLACE INTO files (
        path, name, normalized_name, is_folder, parent_path,
        modified_at, file_size
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
    """
    
    var statement: OpaquePointer?
    
    if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
      sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
      sqlite3_bind_text(statement, 2, name, -1, SQLITE_TRANSIENT)
      sqlite3_bind_text(
        statement,
        3,
        normalizedSearchText(name),
        -1,
        SQLITE_TRANSIENT
      )
      sqlite3_bind_int(statement, 4, isFolder ? 1 : 0)
      sqlite3_bind_text(statement, 5, parentPath, -1, SQLITE_TRANSIENT)
      if let modifiedAt = metadata.modifiedAt {
        sqlite3_bind_double(statement, 6, modifiedAt)
      } else {
        sqlite3_bind_null(statement, 6)
      }
      if let size = metadata.size {
        sqlite3_bind_int64(statement, 7, size)
      } else {
        sqlite3_bind_null(statement, 7)
      }
      
      sqlite3_step(statement)
      sqlite3_finalize(statement)
    }
  }
  
  func searchFiles(query: String, sort: String) -> [File] {
    let normalizedQuery = normalizedSearchText(
      query.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    if normalizedQuery.isEmpty {
      return []
    }

    var results: [File] = []
    let orderBy = (FileSearchSort(rawValue: sort) ?? .nameAscending)
      .orderByClause
    
    queue.sync { [weak self] in
      guard let self = self, let db = self.db else { return }
      
      let searchSQL = """
        SELECT path, name, is_folder,
          COALESCE(modified_at, 0), COALESCE(file_size, 0)
        FROM files
        WHERE instr(normalized_name, ?) > 0
        ORDER BY \(orderBy)
        LIMIT 1000
      """
      
      var statement: OpaquePointer?
      
      if sqlite3_prepare_v2(db, searchSQL, -1, &statement, nil) == SQLITE_OK {
        sqlite3_bind_text(statement, 1, normalizedQuery, -1, SQLITE_TRANSIENT)
        while sqlite3_step(statement) == SQLITE_ROW {
          if let cPath = sqlite3_column_text(statement, 0),
             let cName = sqlite3_column_text(statement, 1) {
            let path = String(cString: cPath)
            let name = String(cString: cName)
            let isFolder = sqlite3_column_int(statement, 2) != 0
            let modifiedAt = sqlite3_column_double(statement, 3)
            let size = sqlite3_column_int64(statement, 4)
            
            results.append(File(
              path: path,
              name: name,
              is_folder: isFolder,
              modifiedAt: modifiedAt,
              size: size
            ))
          }
        }
        
        sqlite3_finalize(statement)
      }
    }
    
    return results
  }
  
  func clearIndex() {
    queue.async { [weak self] in
      guard let self = self, let db = self.db else { return }
      sqlite3_exec(db, "DELETE FROM files;", nil, nil, nil)
    }
  }
  
  deinit {
    if let db = db {
      sqlite3_close(db)
    }
  }
}
