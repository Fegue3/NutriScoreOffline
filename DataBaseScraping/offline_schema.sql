-- offline_schema.sql  (SQLite)

PRAGMA foreign_keys = ON;

-- ========== ENUMS (via CHECK) ==========
-- NutriGrade: A..E
-- MealType: BREAKFAST/LUNCH/DINNER/SNACK
-- Unit: GRAM/ML/PIECE
-- Sex: MALE/FEMALE/OTHER

-- ========== USERS ==========
CREATE TABLE IF NOT EXISTS User (
  id                  TEXT PRIMARY KEY,             -- uuid gerado no app
  email               TEXT UNIQUE NOT NULL,
  passwordHash        TEXT NOT NULL,                -- hash local
  refreshTokenHash    TEXT,                         -- não usado no offline MVP
  name                TEXT,
  createdAt           TEXT NOT NULL DEFAULT (datetime('now')),
  updatedAt           TEXT NOT NULL DEFAULT (datetime('now')),
  onboardingCompleted INTEGER NOT NULL DEFAULT 0    -- 0=false,1=true
);

CREATE TRIGGER IF NOT EXISTS trg_User_updatedAt
AFTER UPDATE ON User
BEGIN
  UPDATE User SET updatedAt = datetime('now') WHERE id = NEW.id;
END;

-- ========== USER GOALS ==========
CREATE TABLE IF NOT EXISTS UserGoals (
  userId          TEXT PRIMARY KEY,
  sex             TEXT CHECK (sex IN ('MALE','FEMALE','OTHER')),
  dateOfBirth     TEXT,                 -- ISO 8601
  heightCm        INTEGER,
  currentWeightKg REAL,
  targetWeightKg  REAL,
  targetDate      TEXT,
  activityLevel   TEXT,

  lowSalt         INTEGER NOT NULL DEFAULT 0,
  lowSugar        INTEGER NOT NULL DEFAULT 0,
  vegetarian      INTEGER NOT NULL DEFAULT 0,
  vegan           INTEGER NOT NULL DEFAULT 0,
  allergens       TEXT,

  dailyCalories   INTEGER,
  carbPercent     INTEGER,
  proteinPercent  INTEGER,
  fatPercent      INTEGER,

  updatedAt       TEXT NOT NULL DEFAULT (datetime('now')),

  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE
);

CREATE TRIGGER IF NOT EXISTS trg_UserGoals_updatedAt
AFTER UPDATE ON UserGoals
BEGIN
  UPDATE UserGoals SET updatedAt = datetime('now') WHERE userId = NEW.userId;
END;

-- ========== PRODUCT ==========
CREATE TABLE IF NOT EXISTS Product (
  id                  TEXT PRIMARY KEY, -- uuid
  barcode             TEXT UNIQUE NOT NULL,
  name                TEXT NOT NULL,
  brand               TEXT,
  quantity            TEXT,
  servingSize         TEXT,
  imageUrl            TEXT,
  countries           TEXT,

  nutriScore          TEXT CHECK (nutriScore IN ('A','B','C','D','E')),
  nutriScoreScore     INTEGER,
  novaGroup           INTEGER,          -- 1..4
  ecoScore            TEXT,             -- 'a'..'e' livre (string)

  categories          TEXT,
  labels              TEXT,
  allergens           TEXT,
  ingredientsText     TEXT,

  energyKcal_100g     INTEGER,
  proteins_100g       REAL,
  carbs_100g          REAL,
  sugars_100g         REAL,
  fat_100g            REAL,
  satFat_100g         REAL,
  fiber_100g          REAL,
  salt_100g           REAL,
  sodium_100g         REAL,

  energyKcal_serv     INTEGER,
  proteins_serv       REAL,
  carbs_serv          REAL,
  sugars_serv         REAL,
  fat_serv            REAL,
  satFat_serv         REAL,
  fiber_serv          REAL,
  salt_serv           REAL,
  sodium_serv         REAL,

  lastFetchedAt       TEXT NOT NULL DEFAULT (datetime('now')),
  createdAt           TEXT NOT NULL DEFAULT (datetime('now')),
  updatedAt           TEXT NOT NULL DEFAULT (datetime('now')),

  off_raw             TEXT               -- JSON como string
);

CREATE INDEX IF NOT EXISTS idx_Product_name ON Product(name);
CREATE INDEX IF NOT EXISTS idx_Product_brand ON Product(brand);
CREATE INDEX IF NOT EXISTS idx_Product_categories ON Product(categories);

CREATE TRIGGER IF NOT EXISTS trg_Product_updatedAt
AFTER UPDATE ON Product
BEGIN
  UPDATE Product SET updatedAt = datetime('now') WHERE id = NEW.id;
END;

-- ========== PRODUCT HISTORY ==========
CREATE TABLE IF NOT EXISTS ProductHistory (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  userId      TEXT NOT NULL,
  barcode     TEXT,
  scannedAt   TEXT NOT NULL DEFAULT (datetime('now')),
  nutriScore  TEXT CHECK (nutriScore IN ('A','B','C','D','E')),
  calories    INTEGER,
  proteins    REAL,
  carbs       REAL,
  fat         REAL,

  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE,
  FOREIGN KEY (barcode) REFERENCES Product(barcode) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_ProductHistory_user_date ON ProductHistory(userId, scannedAt);
CREATE INDEX IF NOT EXISTS idx_ProductHistory_barcode ON ProductHistory(barcode);

-- ========== FAVORITE PRODUCT ==========
CREATE TABLE IF NOT EXISTS FavoriteProduct (
  userId      TEXT NOT NULL,
  barcode     TEXT NOT NULL,
  createdAt   TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (userId, barcode),
  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE,
  FOREIGN KEY (barcode) REFERENCES Product(barcode) ON DELETE CASCADE
);

-- ========== CUSTOM FOOD ==========
CREATE TABLE IF NOT EXISTS CustomFood (
  id              TEXT PRIMARY KEY,  -- uuid
  userId          TEXT NOT NULL,
  name            TEXT NOT NULL,
  brand           TEXT,
  defaultUnit     TEXT NOT NULL DEFAULT 'GRAM' CHECK (defaultUnit IN ('GRAM','ML','PIECE')),
  gramsPerUnit    REAL,

  energyKcal_100g INTEGER,
  proteins_100g   REAL,
  carbs_100g      REAL,
  sugars_100g     REAL,
  fat_100g        REAL,
  satFat_100g     REAL,
  fiber_100g      REAL,
  salt_100g       REAL,
  sodium_100g     REAL,

  createdAt       TEXT NOT NULL DEFAULT (datetime('now')),
  updatedAt       TEXT NOT NULL DEFAULT (datetime('now')),

  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE
);

CREATE TRIGGER IF NOT EXISTS trg_CustomFood_updatedAt
AFTER UPDATE ON CustomFood
BEGIN
  UPDATE CustomFood SET updatedAt = datetime('now') WHERE id = NEW.id;
END;

-- ========== CUSTOM MEAL ==========
CREATE TABLE IF NOT EXISTS CustomMeal (
  id            TEXT PRIMARY KEY,
  userId        TEXT NOT NULL,
  name          TEXT NOT NULL,
  totalKcal     INTEGER,
  totalProtein  REAL,
  totalCarb     REAL,
  totalFat      REAL,

  createdAt     TEXT NOT NULL DEFAULT (datetime('now')),
  updatedAt     TEXT NOT NULL DEFAULT (datetime('now')),

  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE
);

CREATE TRIGGER IF NOT EXISTS trg_CustomMeal_updatedAt
AFTER UPDATE ON CustomMeal
BEGIN
  UPDATE CustomMeal SET updatedAt = datetime('now') WHERE id = NEW.id;
END;

-- ========== CUSTOM MEAL ITEM ==========
CREATE TABLE IF NOT EXISTS CustomMealItem (
  id              TEXT PRIMARY KEY,
  customMealId    TEXT NOT NULL,

  customFoodId    TEXT,
  productBarcode  TEXT,

  unit            TEXT NOT NULL DEFAULT 'GRAM' CHECK (unit IN ('GRAM','ML','PIECE')),
  quantity        REAL NOT NULL,  -- 150.00
  gramsTotal      REAL,

  kcal            INTEGER,
  protein         REAL,
  carb            REAL,
  fat             REAL,

  position        INTEGER,

  FOREIGN KEY (customMealId) REFERENCES CustomMeal(id) ON DELETE CASCADE,
  FOREIGN KEY (customFoodId) REFERENCES CustomFood(id) ON DELETE SET NULL,
  FOREIGN KEY (productBarcode) REFERENCES Product(barcode) ON DELETE SET NULL
);

-- ========== MEAL (LOG DIÁRIO) ==========
CREATE TABLE IF NOT EXISTS Meal (
  id            TEXT PRIMARY KEY,
  userId        TEXT NOT NULL,
  date          TEXT NOT NULL,  -- "YYYY-MM-DDT00:00:00Z" (canon UTC)
  type          TEXT NOT NULL CHECK (type IN ('BREAKFAST','LUNCH','DINNER','SNACK')),
  notes         TEXT,

  totalKcal     INTEGER,
  totalProtein  REAL,
  totalCarb     REAL,
  totalFat      REAL,

  createdAt     TEXT NOT NULL DEFAULT (datetime('now')),
  updatedAt     TEXT NOT NULL DEFAULT (datetime('now')),

  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE,
  UNIQUE (userId, date, type)
);

CREATE INDEX IF NOT EXISTS idx_Meal_user_date ON Meal(userId, date);

CREATE TRIGGER IF NOT EXISTS trg_Meal_updatedAt
AFTER UPDATE ON Meal
BEGIN
  UPDATE Meal SET updatedAt = datetime('now') WHERE id = NEW.id;
END;

-- ========== MEAL ITEM ==========
CREATE TABLE IF NOT EXISTS MealItem (
  id              TEXT PRIMARY KEY,
  mealId          TEXT NOT NULL,

  productBarcode  TEXT,
  customFoodId    TEXT,

  unit            TEXT NOT NULL DEFAULT 'GRAM' CHECK (unit IN ('GRAM','ML','PIECE')),
  quantity        REAL NOT NULL,
  gramsTotal      REAL,

  kcal            INTEGER,
  protein         REAL,
  carb            REAL,
  fat             REAL,
  sugars          REAL,
  fiber           REAL,
  salt            REAL,

  position        INTEGER,
  userId          TEXT,  -- opcional (audit)

  FOREIGN KEY (mealId) REFERENCES Meal(id) ON DELETE CASCADE,
  FOREIGN KEY (productBarcode) REFERENCES Product(barcode) ON DELETE SET NULL,
  FOREIGN KEY (customFoodId) REFERENCES CustomFood(id) ON DELETE SET NULL,
  FOREIGN KEY (userId) REFERENCES User(id)
);

-- ========== DAILY STATS ==========
CREATE TABLE IF NOT EXISTS DailyStats (
  userId    TEXT NOT NULL,
  date      TEXT NOT NULL,  -- canónico
  kcal      INTEGER NOT NULL DEFAULT 0,
  protein   REAL    NOT NULL DEFAULT 0,
  carb      REAL    NOT NULL DEFAULT 0,
  fat       REAL    NOT NULL DEFAULT 0,
  sugars    REAL    NOT NULL DEFAULT 0,
  fiber     REAL    NOT NULL DEFAULT 0,
  salt      REAL    NOT NULL DEFAULT 0,

  createdAt TEXT NOT NULL DEFAULT (datetime('now')),
  updatedAt TEXT NOT NULL DEFAULT (datetime('now')),

  PRIMARY KEY (userId, date),
  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_DailyStats_user_date ON DailyStats(userId, date);

CREATE TRIGGER IF NOT EXISTS trg_DailyStats_updatedAt
AFTER UPDATE ON DailyStats
BEGIN
  UPDATE DailyStats SET updatedAt = datetime('now') WHERE userId = NEW.userId AND date = NEW.date;
END;


-- ========== WEIGHT LOG ==========
CREATE TABLE IF NOT EXISTS WeightLog (
  id         TEXT PRIMARY KEY,
  userId     TEXT NOT NULL,
  day        TEXT NOT NULL,  -- "YYYY-MM-DD"
  weightKg   REAL NOT NULL,
  source     TEXT,
  note       TEXT,
  createdAt  TEXT NOT NULL DEFAULT (datetime('now')),

  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_WeightLog_user_day ON WeightLog(userId, day);
