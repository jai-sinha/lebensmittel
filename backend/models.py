"""
Database models for the Lebensmittel backend application.
"""
from datetime import datetime
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.dialects.postgresql import UUID
import uuid

Base = declarative_base()


class GroceryItem(Base):
    """
    GroceryItem model matching the Swift struct.
    
    Corresponds to:
    struct GroceryItem: Identifiable, Codable {
        var id = UUID()
        var name: String
        var category: String
        var isNeeded: Bool = true // true = need to buy, false = have it
        var isShoppingChecked: Bool = false // checked off in shopping list
    }
    """
    __tablename__ = 'grocery_items'
    
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(255), nullable=False)
    category = Column(String(100), nullable=False)
    is_needed = Column(Boolean, default=True, nullable=False)  # true = need to buy, false = have it
    is_shopping_checked = Column(Boolean, default=False, nullable=False)  # checked off in shopping list
    
    def to_dict(self):
        """Convert model instance to dictionary for JSON serialization."""
        return {
            'id': self.id,
            'name': self.name,
            'category': self.category,
            'isNeeded': self.is_needed,
            'isShoppingChecked': self.is_shopping_checked
        }
    
    def __repr__(self):
        return f"<GroceryItem(id={self.id}, name='{self.name}', category='{self.category}')>"


class MealPlan(Base):
    """
    MealPlan model matching the Swift struct.
    
    Corresponds to:
    struct MealPlan: Identifiable, Codable {
        var id = UUID()
        var date: Date
        var mealDescription: String
    }
    """
    __tablename__ = 'meal_plans'
    
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    date = Column(DateTime, nullable=False)
    meal_description = Column(Text, nullable=False)
    
    def to_dict(self):
        """Convert model instance to dictionary for JSON serialization."""
        return {
            'id': self.id,
            'date': self.date.isoformat() if self.date else None,
            'mealDescription': self.meal_description
        }
    
    def __repr__(self):
        return f"<MealPlan(id={self.id}, date={self.date}, description='{self.meal_description[:50]}...')>"