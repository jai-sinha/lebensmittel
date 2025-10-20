"""
Database configuration and initialization for the Lebensmittel backend.
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from models import Base, GroceryItem, MealPlan
import os

# Database configuration
DATABASE_URL = os.getenv('DATABASE_URL', 'sqlite:///lebensmittel.db')

# Create engine
engine = create_engine(
	DATABASE_URL,
	echo=True if os.getenv('DEBUG') else False,  # Log SQL queries in debug mode
	connect_args={'check_same_thread': False} if 'sqlite' in DATABASE_URL else {}
)

# Create session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def create_tables():
	"""Create all tables in the database."""
	Base.metadata.create_all(bind=engine)
	print("Database tables created successfully!")


def get_db():
	"""
	Dependency to get database session.
	Use this in your Flask routes to get a database session.
	"""
	db = SessionLocal()
	try:
		yield db
	finally:
		db.close()


def init_db():
	"""Initialize the database with tables."""
	create_tables()


if __name__ == "__main__":
	init_db()